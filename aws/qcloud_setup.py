#!/usr/bin/env python3

import pprint

import os
import re
import sys
import pathlib
import argparse
import configparser

import botocore
import boto3

from pcluster.configure.utils import (
   get_regions,
   prompt,
   prompt_iterable
)

from pcluster.configure.networking import (
   NetworkConfiguration,
   PublicPrivateNetworkConfig,
   automate_vpc_with_subnet_creation,
)

from pcluster.utils import (
   get_region,
   get_default_instance_type,
   get_supported_compute_instance_types,
   get_supported_instance_types,
   get_supported_os_for_scheduler,
   get_supported_az_for_one_instance_type
)

from pcluster.config.validators import (
    HEAD_NODE_UNSUPPORTED_INSTANCE_TYPES, 
    HEAD_NODE_UNSUPPORTED_MESSAGE
)


class PClusterConfig:
      def __init__(self, config_file, label):
          self.config_file = config_file
          self.label = label
          self.parser = configparser.ConfigParser()

          if config_file and os.path.exists(config_file) and not os.path.isfile(config_file):
             error("Invalid configuration file path: {0}".format(config_file))
          if os.path.exists(args.config_file):
             msg = "Configuration file {0} will be loaded and overwritten."
             print(msg.format(config_file))
             self.parser.read(config_file)
          else:
             msg = "INFO: Configuration file {0} will be written."
             print(msg.format(config_file))
             print("Press CTRL-C to interrupt the procedure.\n")

      def get(self, section, option, default=None):
          if not self.parser.has_section(section): return default
          if not self.parser.has_option(section, option): return default
          return self.parser.get(section, option)

      def set(self, section, option, value):
          if not self.parser.has_section(section): self.parser.add_section(section)
          self.parser.set(section, option, str(value))

      def max_cluster_size(self):
          sections = self.parser.sections() 
          s = "compute_resource {0}".format(self.label)
          n = 0
          for section in sections:
             if s in section: n += int(self.get(section, "max_count",0))
          return n
              
      def node_types(self):
          sections = self.parser.sections() 
          s = "compute_resource {0}".format(self.label)
          node_types = []
          for section in sections:
             if s in section: 
                it = node_types.append(self.get(section, "instance_type"))
                if it: node_types.append(it)
          return node_types

          if type: node_types.append(type)
          node_types.append("c5.large")
          print("Node types:", node_types)
          return node_types

      def dump(self):
          self.parser.write(sys.stdout)

      def write(self):
          with open(self.config_file, 'w') as cfg:
             self.parser.write(cfg)


def instance_type_supported_for_head_node(instance_type):
    if instance_type in HEAD_NODE_UNSUPPORTED_INSTANCE_TYPES:
        print(HEAD_NODE_UNSUPPORTED_MESSAGE.format(instance_type))
        return False
    return True


def get_aws_keys():
    """Return a list of valid AWS keys."""
    keypairs = boto3.client("ec2").describe_key_pairs()
    key_options = []
    for key in keypairs.get("KeyPairs"):
        key_name = key.get("KeyName")
        key_options.append(key_name)

    if not key_options:
       print(
          "No KeyPair found in region {0}, please create one following the guide: "
          "https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html".format(get_region())
        )

    return key_options


def choose_network_configuration(node_types):
    if not node_types:
       print("ERROR: No instance types available in configuration")
       print("       Unable to configure VPC networking")
       print("Exiting...")
       sys.exit(1)

    common_availability_zones = get_supported_az_for_one_instance_type(node_types[0])
    for node_type in node_types:
        node_azs = get_supported_az_for_one_instance_type(node_type)
        common_availability_zones = set(common_availability_zones) & set(node_azs)
       
    if not common_availability_zones:
       # Automate subnet creation only allows subnets to reside in a single az.
       # But user can bypass it by using manual subnets creation during configure 
       #or modify the config file directly.
       print(
          "Error: There is no single availability zone offering head node and compute in current region.\n"
          "To create your cluster, make sure you have a subnet for head node in {0}"
          ", and a subnet for compute nodes in {1}. Then run pcluster configure again"
          "and avoid using Automate VPC/Subnet creation.".format(head_node_azs, compute_node_azs))
       print("Exiting...")
       sys.exit(1)

    target_type = prompt_iterable("Network Configuration",
       options=[configuration.value.config_type for configuration in NetworkConfiguration],
       default_value=PublicPrivateNetworkConfig().config_type)

    network_configuration = next(
       configuration.value for configuration in NetworkConfiguration if configuration.value.config_type == target_type
    )
    network_configuration.availability_zones = common_availability_zones
    return network_configuration


#TODO this needs to handle the presence of an existing sg that doesn't have the ports open
#TODO the port numbers are hard wired an should be obtained from qcloud.cfg
def create_security_group(label, vpc_id):
    group_id = ''
    try:
       client = boto3.client('ec2')
       response = client.create_security_group(
          Description = "QCloud security group",
          GroupName = label + "-sg",
          VpcId = vpc_id
       )
       #print(response)
       group_id = response['GroupId']
       print("GroupID = ",  group_id)
       data = client.authorize_security_group_ingress(
           GroupId = group_id,
           IpPermissions = [
               {'IpProtocol': 'tcp',
                'FromPort': 8883,
                'ToPort': 8883,
                'IpRanges': [{'CidrIp': '0.0.0.0/0', 'Description': 'qcweb'}]},
               {'IpProtocol': 'tcp',
                'FromPort': 8882,
                'ToPort': 8882,
                'IpRanges': [{'CidrIp': '0.0.0.0/0', 'Description': 'qcauth'}]},
               {'IpProtocol': 'tcp',
                'FromPort': 55555,
                'ToPort': 55555,
                'IpRanges': [{'CidrIp': '0.0.0.0/0', 'Description': 'flexnet'}]},
               {'IpProtocol': 'tcp',
                'FromPort': 27000,
                'ToPort': 27010,
                'IpRanges': [{'CidrIp': '0.0.0.0/0', 'Description': 'flexnet ports'}]}
           ])

       #print('Ingress Successfully Set %s' % data)

    except client.exceptions.ClientError as err:
       # TODO parse err to see if group already exists
       print(err)

    return group_id


def create_vpc(config):
    vpc_parameters = {}
    node_types = config.node_types()
    min_subnet_size = int(config.max_cluster_size())
    network_config = choose_network_configuration(node_types)

    vpc_parameters.update(automate_vpc_with_subnet_creation(network_config, min_subnet_size))
    if (network_config.template_name == 'public-private'):
       print("WARNING: A NAT gateway has been created and is being charged per hour")
    return vpc_parameters


def make_queue(label, spot):
    queue_parameters = {}
    queue_parameters['enable_efa']     = 'false'
    queue_parameters['enable_efa_gdr'] = 'false'
    queue_parameters['compute_resource_settings'] = label
    if spot: queue_parameters['compute_type'] = 'spot'
    return queue_parameters


def make_compute_resources(instance_type, max_count, spot_price):
    compute_resources = {}
    compute_resources['instance_type'] = instance_type
    compute_resources['initial_count'] = 0
    compute_resources['min_count']     = 0
    compute_resources['max_count']     = max_count
    if spot_price > 0: compute_resources['spot_price'] = spot_price
    return compute_resources


def get_comp_instances(family, amd, ssd):
    all = get_supported_compute_instance_types("slurm")
    filter = family
    if amd: filter += "a" 
    if ssd: filter += "d" 
    filter += "." 
    avail = [k for k in all if filter in k]

    client = boto3.client('ec2')
    response = client.describe_instance_types(
       DryRun = False,
       InstanceTypes = avail,
       Filters = [ { 'Name': 'bare-metal', 'Values': [ 'false' ] } ] )

    instances = {}
    for key in response['InstanceTypes']:
        instances[key['InstanceType']] = key['VCpuInfo']['DefaultCores']

    return sorted( ((v,k) for k,v in instances.items()))


def prompt_queue_types(config):
    spot_price = -1.0
    amd = prompt("Compute node processor type? (intel/amd)",
       lambda x: x in ("amd", "intel"), default_value="intel") == "amd"
    ssd = prompt("Use SSD drives? (y/n)",
       lambda x: x in ("y", "n"), default_value="n") == "y"
    spot = prompt("On demand or spot pricing? (ondemand/spot)",
       lambda x: x in ("ondemand", "spot"), default_value="ondemand") == "spot"
    if (spot):
       spot_price = prompt("Spot pricing cap",
          lambda x: str(x).replace('.','',1).isdigit() and float(x) > 0, default_value=0.5)

    # We only consider the c5* family for the time being.
    instances = get_comp_instances("c5", amd, ssd)
    cores = []
    for k, v in instances:
        print("{0}: ({1})".format(k,v))
        cores.append(k)

    # A maximum of 5 queue types are supported
    default_value = cores[4] if len(cores) >= 5 else cores[-1]
    max_node_size = prompt("Maximum cores/node size",
       lambda x: int(x) in cores, default_value=default_value)
    queue_nodes = prompt("Maximum nodes/queue",
       lambda x: str(x).isdigit() and int(x) >= 0, default_value=10)

    queue_labels = []
    for q in range(cores.index(int(max_node_size))+1):
        core_count   = cores[q]
        queue_label  = '{0}{1}'.format(config.label,core_count)
        section_name = "queue {0}".format(queue_label)
        queue_params = make_queue(queue_label,spot)
        for k,v in queue_params.items():
            config.set(section_name, k, v)
        section_name = "compute_resource {0}".format(queue_label)
        resources    = make_compute_resources(instances[q][1], queue_nodes, spot_price)
        for k,v in resources.items():
            config.set(section_name, k, v)
        queue_labels.append(queue_label)

    return queue_labels
    

def configure_pcluster(args):
    config  = PClusterConfig(args.config_file, args.label)
    label   = args.label
    verbose = args.verbose

    # [aws]
    # aws_region_name = config.get("aws", "aws_region_name")
    aws_region_name = "us-east-1"
    if not aws_region_name:
       available_regions = get_regions()
       session = boto3.session.Session()
       default_region = session.region_name
       aws_region_name = prompt_iterable("AWS Region ID", 
          available_regions, default_value=default_region)
       config.set("aws", "aws_region_name", aws_region_name)
       print("Region set to ", aws_region_name)

    config.set("aws", "aws_region_name", aws_region_name)
    os.environ["AWS_DEFAULT_REGION"] = aws_region_name
    
    # [global]
    section_name = "global"
    if config.parser.has_section(section_name):
       if verbose: print("Found exisiting {0} section".format(section_name))
    else:
       config.set(section_name, "cluster_template", label)
       config.set(section_name, "update_check", "true")
       config.set(section_name, "sanity_check", "true")

    # [aliases]
    section_name = "aliases"
    config.set(section_name, "ssh", "ssh {CFN_USER}@{MASTER_IP} {ARGS}")

    # [cluster]
    scheduler = "slurm"
    section_name = "cluster {0}".format(label)
    config.set(section_name, "scheduler", scheduler)
    config.set(section_name, "vpc_settings", label)
    config.set(section_name, "ebs_settings", label)

    qcloud_ami = "ami-09f661a138c1eb411"  
    config.set(section_name, "custom_ami", qcloud_ami)

    key_name = config.get(section_name, "key_name")
    if not key_name:
       key_name = prompt_iterable("EC2 Key Pair Name", get_aws_keys())
       config.set(section_name, "key_name", key_name)

    # The user cannot change this as it requires generating an AMI for each OS
    base_os = "alinux2"
    config.set(section_name, "base_os", base_os)

    master_instance_type = config.get(section_name, "master_instance_type")
    if not master_instance_type:
       default_instance_type = get_default_instance_type()
       master_instance_type = prompt("Head node instance type",
          lambda x: instance_type_supported_for_head_node(x) and x in get_supported_instance_types(),
          default_value=default_instance_type)
       config.set(section_name, "master_instance_type", master_instance_type)

    # [queue xxx]
    sections = config.parser.sections()
    if any("queue {0}".format(label) in s for s in sections):
       if verbose: 
          print("Found {0} exisiting queues".format(sum("queue {0}".format(label) in s for s in sections)))
    else:
       queues = prompt_queue_types(config)
       section_name = "cluster {0}".format(label)
       config.set(section_name, "queue_settings", ", ".join(queues))

    # [ebs]
    section_name = "ebs {0}".format(label)
    if config.parser.has_section(section_name):
       if verbose: print("Found exisiting {0} section".format(section_name))
    else:
       config.set(section_name, "shared_dir",  "shared")
       #config.set(section_name, "volume_type", "st1")
       config.set(section_name, "volume_type", "gp2")
       ebs_size = prompt("Shared storage size (Gb)",
          lambda x: str(x).isdigit() and int(x) >= 0, default_value=10)
       config.set(section_name, "volume_size", ebs_size)

    # [s3]
    # TODO

    # [scaling]
    section_name = "scaling {0}".format(label)
    if config.parser.has_section(section_name):
       if verbose: print("Found exisiting {0} section".format(section_name))
    else:
       idle_time = prompt("Maximum idle time for compute nodes (mins)",
          lambda x: str(x).isdigit() and int(x) >= 0, default_value=5)
       config.set(section_name, "scaledown_idletime", idle_time)

    # [vpc]
    section_name = "vpc {0}".format(label)
    if config.parser.has_section(section_name):
       if verbose: print("Found exisiting {0} section".format(section_name))
    else:
       vpc_parameters = create_vpc(config)
       for k,v in vpc_parameters.items():
           config.set(section_name, k, v)
       vpc_id =  vpc_parameters['vpc_id']
       print("Created VPC: {0}".format(vpc_id))
       security_group = create_security_group(label, vpc_parameters['vpc_id'])
       config.set(section_name, "additional_sg", security_group)

    config.write()
    print("Cluster configuration written to {0})".format(args.config_file))
    print("Run './qcloud_setup.py --start' to start the cluster")



def pcluster_create(args):
    try:
       config_file = args.config_file
       label = args.label
       print("Creating VPC cluster {0} with config file {1}".format(label,config_file))
       cmd = "pcluster create -c {1} {0} --norollback".format(label,config_file);
       cmd = cmd.split()
       code = os.spawnvpe(os.P_WAIT, cmd[0], cmd, os.environ)
       if code == 127:
          sys.stderr.write('{0}: command not found\n'.format(cmd[0]))

    except:
       print("Unable to create cluster:", sys.exc_info()[0])
       sys.exit(1)


def pcluster_info(args):
    try:
       config_file = args.config_file
       label = args.label
       cmd = "pcluster status -c {1} {0}".format(label,config_file);
       cmd = cmd.split()
       code = os.spawnvpe(os.P_WAIT, cmd[0], cmd, os.environ)
       if code == 127:
          sys.stderr.write('{0}: command not found\n'.format(cmd[0]))

    except:
       print("Unable to create cluster:", sys.exc_info()[0])
       sys.exit(1)




def pcluster_start(args):
    try:
       config_file = args.config_file
       label = args.label
       print("Starting VPC cluster {0} with config file {1}".format(label,config_file))
       cmd = "pcluster start -c {1} {0}".format(label,config_file);
       cmd = cmd.split()
       code = os.spawnvpe(os.P_WAIT, cmd[0], cmd, os.environ)
       if code == 127:
          sys.stderr.write('{0}: command not found\n'.format(cmd[0]))
       else:
          print("Run the following command on the head node to get the license information:\n")
          print("/opt/flexnet-11.18.0/bin/lmutil lmhostid -ptype AMZN -iid\n");


    except:
       print("Unable to start cluster:", sys.exc_info()[0])
       sys.exit(1)



def pcluster_delete(args):
    try:
       config_file = args.config_file
       label = args.label
       print("Deleting VPC cluster {0} with config file {1}".format(label,config_file))
       print("This will delete all AWS resources accociated with this cluster, including storage.")
       response = input("Coninue? [y/N]")

       if (response == 'y' or response == 'yes'):
          cmd = "pcluster delete {0}".format(label);
          cmd = cmd.split()
          code = os.spawnvpe(os.P_WAIT, cmd[0], cmd, os.environ)
          if code == 127:
             sys.stderr.write('{0}: command not found\n'.format(cmd[0]))

    except:
       print("Unable to delete cluster:", sys.exc_info()[0])
       sys.exit(1)




def configure_aws_cli():
    print("Configuring AWS CLI client")
    print("If you have not already done so, you will need to create an access key and")
    print("password pair in the AWS console under the Identity and Access Management")
    print("(IAM) panel.  If you have already done this, these details will be provided")
    print("as defaults.")

    cmd = [ "aws", "configure" ]
    code = os.spawnvpe(os.P_WAIT, cmd[0], cmd, os.environ)
    if code == 127:
        sys.stderr.write('{0}: command not found\n'.format(cmd[0]))
    return code


def create_account():
    client = boto3.client("iam")

    group = prompt("QCloud group", 
       validator=lambda x: x[0].isalpha() and re.match('^[\w-]+$', x), default_value="qcloud")

    try:
       print("Creating group {0}".format(group))
       client.create_group( GroupName=group )
       print("Attaching policies")
       client.attach_group_policy(
          GroupName=group,
          PolicyArn='arn:aws:iam::aws:policy/AmazonEC2FullAccess',
       )
       client.attach_group_policy(
          GroupName=group,
          PolicyArn='arn:aws:iam::aws:policy/AmazonS3FullAccess'
       )
    except client.exceptions.EntityAlreadyExistsException:
       print("Using existing group {0}".format(group))
    except client.exceptions.PolicyNotAttachableException:
       print("Unable to attach required group policies")
       sys.exit(1)

    admin = prompt("QCloud administrator account",
       validator=lambda x: x[0].isalpha() and re.match('^[\w-]+$', x), default_value=group+"-admin")

    try:
       print("Creating user {0}".format(admin))
       client.create_user( UserName=admin )
       client.add_user_to_group( UserName=admin, GroupName=group )
       print("Creating access keys")
       response = client.create_access_key( UserName=admin )
       aws_access_key_id = response['AccessKey']['AccessKeyId']
       aws_secret_access_key = response['AccessKey']['SecretAccessKey']

       print("Setting access keys for profile {0}".format(admin))
       cmd = "aws configure set aws_access_key_id {0} --profile {1}".format(aws_access_key_id, admin)
       cmd = cmd.split()
       code = os.spawnvpe(os.P_WAIT, cmd[0], cmd, os.environ)
       if code == 127:
          sys.stderr.write('{0}: command not found\n'.format(cmd[0]))
          raise KeyError;
       cmd = "aws configure set aws_secret_access_key {0} --profile {1}".format(aws_secret_access_key, admin)
       cmd = cmd.split()
       code = os.spawnvpe(os.P_WAIT, cmd[0], cmd, os.environ)
       if code == 127:
          sys.stderr.write('{0}: command not found\n'.format(cmd[0]))
          raise KeyError; 
       # TODO: need to cache profile determined by admin for later use
       #       env var?

    except client.exceptions.EntityAlreadyExistsException:
       print("Using existing user account {0}".format(admin))
    except client.exceptions.NoSuchEntityException:
       print("Unable to configure admin user {0}".format(admin))
       sys.exit(1)
    except KeyError:
       print("Unable to configure access keys")
       sys.exit(1)



if __name__ == "__main__":
   #create_security_group("qcloud", "vpc-2c8b6a4a")
   #sys.exit(1)

   parser = argparse.ArgumentParser();
   parser.add_argument("-f", "--file", dest="config_file", default="qcloud.config", 
       help="Defines an alternative config file.")

   parser.add_argument("-v", "--verbose", dest="verbose", action='store_true',
       help="Increase printout level")

   parser.add_argument("-l", "--label", dest="label", default="qcloud",
       help="Name of the cluster")

   parser.add_argument("-k", "--keygen", dest="keygen",  action='store_true',
       help="Generate keys")

   parser.add_argument("-s", "--start", dest="start",  action='store_true',
       help='Start the cluster')

   parser.add_argument("-x", "--delete", dest="delete",  action='store_true',
       help='Delete the cluster')

   parser.add_argument("-i", "--info", dest="info",  action='store_true',
       help='Get information on the cluster')

   parser.add_argument("-c", "--config", dest="config",  action='store_true',
       help='Configure the cluster')

   args, extra_args = parser.parse_known_args()

   if args.keygen:
      configure_aws_cli()
      create_account()

   elif args.start:
      pcluster_create(args)
      pcluster_start(args)

   elif args.info:
      pcluster_info(args)

   elif args.delete:
      pcluster_delete(args)

   elif args.config:
      configure_pcluster(args)

   else:
      configure_pcluster(args)


