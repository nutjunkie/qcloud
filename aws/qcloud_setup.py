#!/usr/bin/env python3


import os
import re
import sys
import time
import json
import uuid
import pprint
import pathlib
import argparse
import configparser
import subprocess

import botocore
import boto3

from future.backports import datetime
from operator import attrgetter

from pcluster.configure.utils import (
   get_regions,
   prompt,
   prompt_iterable
)

from pcluster.configure.networking import (
   NetworkConfiguration,
   PublicPrivateNetworkConfig
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

from pcluster.networking.vpc_factory import VpcFactory


verbose = 0


def debug(msg):
    if (verbose > 0):
        print(msg)



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
             debug("INFO: Configuration file {0} will be written.".format(config_file))

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



def print_dict(dict):
    print(json.dumps(dict, sort_keys=True, indent=4))



def instance_type_supported_for_head_node(instance_type):
    if instance_type in HEAD_NODE_UNSUPPORTED_INSTANCE_TYPES:
        print(HEAD_NODE_UNSUPPORTED_MESSAGE.format(instance_type))
        return False
    return True



def configure_aws_cli():
    print("Configuring AWS CLI client")
    print("If you have not already done so, you will need to create an access key and")
    print("password pair in the AWS console under the Identity and Access Management")
    print("(IAM) panel.")

    cmd = [ "aws", "configure" ]
    code = os.spawnvpe(os.P_WAIT, cmd[0], cmd, os.environ)
    if code == 127:
        print("{0}: command not found".format(cmd[0]))
        sys.exit(1)
    return code



def create_session():
    session = None

    while (not session):
        try:
            sts_client = boto3.client('sts')
            sts_client.get_caller_identity()
            session = boto3.Session()
            debug("Creating session for region {0}".format(session.region_name))
            os.environ["AWS_DEFAULT_REGION"] = session.region_name

        except (botocore.exceptions.ClientError,
                botocore.exceptions.NoCredentialsError):
            configure_aws_cli()

        except botocore.exceptions.CredentialRetrievalError:
            print("Unable to access AWS credentials")
            sys.exit(1)

    return session


def get_ami(session):
    ami_id = None
    try:
        ec2_resource = session.resource("ec2")
        images = ec2_resource.images.filter(
            Filters=[
                {
                    'Name': 'name',
                    'Values': ['QCloud*']
                }
            ]
        )
        images = sorted(list(images), key=attrgetter('creation_date'), reverse=True)

        for image in images:
            if (not ('setup' in image.name.lower())):
                ami_id = image.id
                print("INFO: Using QCloud AMI {0} {1}".format(image.name, image.id))
                break
        if (not ami_id):
            raise Exception

    except:
        print("Unable to determine QCloud AMI")
        sys.exit(1)

    return ami_id



def get_aws_keys(session):
    """Return a list of valid AWS keys."""
    ec2_client = session.client("ec2")
    keypairs = ec2_client.describe_key_pairs()
    key_options = []
    for key in keypairs.get("KeyPairs"):
        key_name = key.get("KeyName")
        key_options.append(key_name)

    if not key_options:
       print("No KeyPair found in region {0}, please create one following the guide: "
             "https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html".format(get_region()) )
       sys.exit(1)

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
    group_id = None
    group_name = label + "-sg"
    try:
        ec2_client = boto3.client('ec2')

        # First check if there already exists the SG
        response = ec2_client.describe_security_groups(
            Filters=[
                {
                    'Name': 'group-name',
                    'Values': [ group_name ]
                },
                {
                    'Name': 'vpc-id',
                    'Values': [ vpc_id ]
                }
            ]
        )

        if response['SecurityGroups']:
            print ("Found existing security group")
            group_id = response['SecurityGroups'][0]['GroupId']
            return group_id

        debug("Creating security group")
        response = ec2_client.create_security_group(
            Description = "QCloud security group",
            GroupName = group_name,
            VpcId = vpc_id
        )
        time.sleep(3)
        group_id = response['GroupId']

        print("GroupID:     {0}".format(group_id))
        data = ec2_client.authorize_security_group_ingress(
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

    except botocore.exceptions.ClientError as err:
        err = string(err)
        if "InvalidGroup.Duplicate" not in err:
           print(err)

    return group_id



def automate_vpc_with_subnet_creation(network_configuration, compute_subnet_size, region):
    print("Beginning VPC creation. Please do not leave the terminal until the creation is finalized")
    vpc_creator = VpcFactory(region)
    vpc_id = vpc_creator.create()

    client = boto3.resource("ec2", region)
    time.sleep(1)
    vpc = client.Vpc(vpc_id)
    vpc.wait_until_available()

    time_stamp = "-{:%Y%m%d%H%M%S}".format(datetime.datetime.utcnow())
    vpc_creator.setup(vpc_id, name="QCloud-VPC" + time_stamp)

    if not vpc_creator.check(vpc_id):
        logging.critical("Something went wrong in VPC creation. Please delete it and start the process again")
        sys.exit(1)
    if not VpcFactory(region).check(vpc_id):
        logging.error("WARNING: The VPC does not have the correct parameters set.")

    vpc_parameters = {"vpc_id": vpc_id}
    new_parameters = network_configuration.create(vpc_id, compute_subnet_size)
    vpc_parameters.update(new_parameters)
    return vpc_parameters



def create_vpc(session, config):
    vpc_parameters = {}
    node_types = config.node_types()
    min_subnet_size = int(config.max_cluster_size())
    network_config = choose_network_configuration(node_types)
    vpc_parameters.update(automate_vpc_with_subnet_creation(network_config, min_subnet_size, session.region_name))

    if (network_config.template_name == 'public-private'):
       print("WARNING: A NAT gateway has been created and is being charged per hour")
    return vpc_parameters


def get_subnet(session, vpc_id):
    ec2_client = session.client("ec2")
    response = ec2_client.describe_subnets(
        Filters=[
            {'Name': 'vpc_id', 'Values': string(vpc_id) }
        ]
    )
    print(response)
    

def get_vpc(session, config):
    vpc_id = None
    ec2_resource = session.resource("ec2")

    if False:
       # Skip check for time being
       # Check if there is an existing VPC 
       vpcs = ec2_resource.vpcs.all()
       avail = []
       for vpc in vpcs:
           if (vpc.state == 'available'):
              for tag in vpc.tags:
                  val = tag['Value']
                  if 'QCloud-VPC' in val:
                      avail.append("{0}  {1}  {2}".format(vpc.id, val, vpc.state))
       if avail:
           avail.insert(0, "Create new")
           response = prompt_iterable("VPC", avail)
           vpc_id = None if response == "Create new" else response.split()[0]

    vpc_params = {}
    if (vpc_id):
        vpc_params = {"vpc_id": vpc_id}
        print(vpc_params)
        print("WARNING: Incomplete VPC parameter list returned")
        #{'vpc_id': 'vpc-07d21de1c811c55f1', 'master_subnet_id': 'subnet-0ba6b98f5d5d81c55', 'use_public_ips': 'true'}
        #print(vpc_params)
    else:
        vpc_params = create_vpc(session, config)

    return vpc_params



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
    family = prompt("Compute node family: (t2/c5)",
        lambda x: x in ("c5", "t2"), default_value="c5")

    instances = get_comp_instances(family, amd, ssd)
    cores = []
    for k, v in instances:
        print("{0}: ({1})".format(k,v))
        cores.append(k)

    # A maximum of 5 queue types are supported
    default_value = cores[4] if len(cores) >= 5 else cores[-1]
    max_node_size = prompt("Maximum cores/node size",
       lambda x: int(x) in cores, default_value=default_value)
    min_node_size = prompt("Minimum cores/node size",
       lambda x: int(x) in cores, default_value=max_node_size)
    queue_nodes = prompt("Maximum nodes/queue",
       lambda x: str(x).isdigit() and int(x) >= 0, default_value=10)

    queue_labels = []
    min_idx = cores.index(int(min_node_size))
    max_idx = cores.index(int(max_node_size))

    for q in range(min_idx, max_idx+1):
        core_count   = cores[q]
        instance_type = instances[q][1]
        queue_label  = '{0}.{1}.{2}'.format(config.label, instance_type, core_count)
        queue_label = queue_label.replace('.','-')
        queue_label = queue_label.replace(' ','_')
        section_name = "queue {0}".format(queue_label)
        queue_params = make_queue(queue_label,spot)
        for k,v in queue_params.items():
            config.set(section_name, k, v)
        section_name = "compute_resource {0}".format(queue_label)
        resources    = make_compute_resources(instance_type, queue_nodes, spot_price)
        for k,v in resources.items():
            config.set(section_name, k, v)
        queue_labels.append(queue_label)

    print(queue_labels)
    return queue_labels
    


def configure_pcluster(session, args):
    # config file
    config_file = args.config_file
    if (os.path.isfile(config_file)):
        delete = prompt("Delete existing config file {0}? (y/n)".format(config_file),
           lambda x: x in ("y", "n"), default_value="y") == "y"
        if (delete):
            os.remove(config_file)
        else:
            print("Settings from {0} will be used".format(config_file))

    config  = PClusterConfig(args.config_file, args.label)
    label   = args.label
    verbose = args.verbose

    # [aws]
    section_name = "aws"
    config.set(section_name, "aws_region_name", session.region_name)
    config.write()

    # [global]
    section_name = "global"
    if config.parser.has_section(section_name):
        debug("Using exisiting {0} section".format(section_name))
    else:
        config.set(section_name, "cluster_template", label)
        config.set(section_name, "update_check", "true")
        config.set(section_name, "sanity_check", "true")
    config.write()

    # [aliases]
    section_name = "aliases"
    if config.parser.has_section(section_name):
       debug("Using exisiting {0} section".format(section_name))
    else:
        config.set(section_name, "ssh", "ssh {CFN_USER}@{MASTER_IP} {ARGS}")
    config.write()

    # [cluster]
    section_name = "cluster {0}".format(label)
    if config.parser.has_section(section_name):
        if verbose: print("Using exisiting {0} section".format(section_name))
    else:
        config.set(section_name, "scheduler", "slurm")
        config.set(section_name, "vpc_settings", label)
        #config.set(section_name, "ebs_settings", label)
        config.set(section_name, "efs_settings", label)
        qcloud_ami = get_ami(session)
        config.set(section_name, "custom_ami", qcloud_ami)

        key_name = config.get(section_name, "key_name")
        if not key_name:
            key_name = prompt_iterable("EC2 Key Pair Name", get_aws_keys(session))
            config.set(section_name, "key_name", key_name)

        # The user cannot change this as each OS requires and AMI
        base_os = "alinux2"
        config.set(section_name, "base_os", base_os)

        master_instance_type = config.get(section_name, "master_instance_type")
        if not master_instance_type:
            default_instance_type = get_default_instance_type()
            master_instance_type = prompt("Head node instance type",
               lambda x: instance_type_supported_for_head_node(x) and x in get_supported_instance_types(),
               default_value=default_instance_type)
        config.set(section_name, "master_instance_type", master_instance_type)
    config.write()

    # [queue xxx]
    sections = config.parser.sections()
    if any("queue {0}".format(label) in s for s in sections):
        if verbose: 
            print("Using {0} exisiting queues".format(sum("queue {0}".format(label) in s for s in sections)))
    else:
        queues = prompt_queue_types(config)
        section_name = "cluster {0}".format(label)
        config.set(section_name, "queue_settings", ", ".join(queues))
    config.write()

    # [ebs] limits cluster size
    #section_name = "ebs {0}".format(label)
    #if config.parser.has_section(section_name):
    #   if verbose: print("Using exisiting {0} section".format(section_name))
    #else:
    #   config.set(section_name, "shared_dir",  "scratch")
    #   config.set(section_name, "volume_type", "gp2") # also st1
    #   ebs_size = prompt("Scratch size (Gb)",
    #      lambda x: str(x).isdigit() and int(x) >= 0, default_value=10)
    #   config.set(section_name, "volume_size", ebs_size)
    #config.write()

    # [efs]
    section_name = "efs {0}".format(label)
    if config.parser.has_section(section_name):
       if verbose: print("Using exisiting {0} section".format(section_name))
    else:
       config.set(section_name, "shared_dir",  "efs")
       config.set(section_name, "encrypted", "false")
       config.set(section_name, "performance_mode", "generalPurpose")
    config.write()
 
    # [s3]
    # TODO

    # [scaling]
    section_name = "scaling {0}".format(label)
    if config.parser.has_section(section_name):
        if verbose: print("Using exisiting {0} section".format(section_name))
    else:
        idle_time = prompt("Maximum idle time for compute nodes (mins)",
            lambda x: str(x).isdigit() and int(x) >= 0, default_value=5)
        config.set(section_name, "scaledown_idletime", idle_time)
    config.write()

    # [vpc]
    section_name = "vpc {0}".format(label)
    vpc_id = ''
    security_group = ''
    if config.parser.has_section(section_name):
       if verbose: print("Using exisiting {0} section".format(section_name))
    else:
       vpc_parameters = get_vpc(session, config)
       for k,v in vpc_parameters.items():
           config.set(section_name, k, v)
       vpc_id =  vpc_parameters['vpc_id']
       print("Using VPC:  {0}".format(vpc_id))
       security_group = create_security_group(label, vpc_id)
       config.set(section_name, "additional_sg", security_group)
    config.write()

    print("Cluster configuration written to {0}".format(args.config_file))
    print("Run './qcloud_setup.py --start' to start the cluster")



def pcluster_create(label, config_file):
    try:
       print("Creating VPC cluster {0} with config file {1}".format(label,config_file))
       cmd = "pcluster create -c {1} {0} --norollback".format(label,config_file);
       cmd = cmd.split()
       code = os.spawnvpe(os.P_WAIT, cmd[0], cmd, os.environ)
       if code == 127:
          sys.stderr.write('{0}: command not found\n'.format(cmd[0]))

    except:
       print("Unable to create cluster:", sys.exc_info()[0])
       sys.exit(1)



def pcluster_info(session,label):
    try:
        cmd = "pcluster status {0}".format(label)
        res = subprocess.run(cmd.split(), stdout=subprocess.PIPE)
        res = res.stdout.decode('utf-8').split()
        res = {res[i]: res[i + 1] for i in range(0, len(res), 2)}
 
        print("Status:       ", res["Status:"])
        print("Cluster User: ", res["ClusterUser:"])
        print("Master Server:", res["MasterServer:"])
        print("Compute Fleet:", res["ComputeFleetStatus:"])
 
        cmd = "pcluster instances {0}".format(label);
        res = subprocess.run(cmd.split(), stdout=subprocess.PIPE)
        res = res.stdout.decode('utf-8').split()

        names = res[::2]
        iids  = res[1::2]

        if names:
            print("Instances:    ")
            ec2 = session.resource('ec2')
            for r in range(len(names)):
                iid = iids[r]
                instance =  ec2.Instance(iid)
                ip = instance.public_ip_address
                ip = ip if ip else 'private'
                itype = instance.instance_type
                state = instance.state['Name']
                print(f'    {iid:20} {names[r]:13} {ip:15}  {itype:12} {state:13}')
 
    except KeyError as e:
        print("pcluster returned incomplete status data")
        print(e)

    except FileNotFoundError as e:
        print("pcluster: command not found")



def get_master_instance(session, label):
    instance = None
    try:
        cmd = "pcluster instances {0}".format(label);
        res = subprocess.run(cmd.split(), stdout=subprocess.PIPE)
        res = res.stdout.decode('utf-8').split()

        names = res[::2]
        iids  = res[1::2]

        for r in range(len(names)):
            if names[r] == 'MasterServer':
                ec2 = session.resource('ec2')
                instance = ec2.Instance(iids[r])
                break
 
    except FileNotFoundError as e:
        print("pcluster: command not found")

    return instance



def get_vpc_id(session,label):
    vpc_id = None
    instance = get_master_instance(session,label)
    if instance:
        vpc_id = instance.vpc_id
    return vpc_id



def get_master_ip(session,label):
    ip = None
    instance = get_master_instance(session,label)
    if instance:
        ip = instance.public_ip_address
    return ip



def pcluster_command(command, label):
    cmd = "pcluster {0} {1}".format(command,label)
    res = subprocess.run(cmd.split(), stdout=subprocess.PIPE)
    res = res.stdout.decode('utf-8').splitlines()
    res = [x for x in res if not 'pcluster' in x]
    return '\n'.join(res)



def pcluster_update(label, config_file):
    try:
       print(f"Updating VPC cluster {label} with config file {config_file}")
       ret = pcluster_command("stop", label)
       print(ret)
       cmd = f"pcluster update -c {config_file} {label}"
       cmd = cmd.split()
       code = os.spawnvpe(os.P_WAIT, cmd[0], cmd, os.environ)
       if code == 127:
          sys.stderr.write('{0}: command not found\n'.format(cmd[0]))
          return
       ret = pcluster_command("start", label)
       print(ret)

    except:
       print("Unable to create cluster:", sys.exc_info()[0])
       sys.exit(1)


def pcluster_start(label):
    try:
        print("Starting VPC cluster {0}".format(label))
        ret = pcluster_command("start", label)
        print(ret)
        ip = get_master_ip(session,label)
        print("QCloud master node started on {0}".format(ip))
        print("Log into the master node and run the following command to setup Q-Chem")
        print("/home/ec2-user/qchem_install.sh")

    except Exception as e:
        print("Unable to start cluster: " + str(e))



def pcluster_restart(label):
    try:
        print("Restarting VPC cluster {0}".format(label))
        ret = pcluster_command("start",label)
        print(ret)
        ip  = get_master_ip(session,label)
        print("QCloud master node running on {0}".format(ip))
    except Exception as e:
        print("Unable to restart cluster: " + str(e))



def pcluster_stop(label):
    try:
        print("Stopping {0} compute fleet".format(label))
        ret = pcluster_command("stop",label)
        print(ret)
        ip  = get_master_ip(session,label)
    except Exception as e:
        print("Unable to stop cluster: " + str(e))



def delete_nat_gateway(session,nat):
    if (nat['State'] in ["deleted","deleting"]):
        return

    try:
        nat_id = nat['NatGatewayId']
        print("Deleting NAT gateway: {}".format(nat_id))
        ec2 = session.client('ec2')

        ec2.delete_nat_gateway(NatGatewayId=nat_id)
        waiter = ec2.get_waiter('nat_gateway_available')
        waiter.wait(Filters=[
            { 'Name': 'state',          'Values': [ 'deleted' ] },
            { 'Name': 'nat-gateway-id', 'Values': [ nat_id ] }
        ])

    except botocore.exceptions.WaiterError:
        pass
    except botocore.exceptions.ClientError as e:
        if (not nat['State'] in ["deleted","deleting"]):
            print("Unable to delete NAT gateway {}: ".format(nat_id) + str(e))


def release_eip_address(session,eip):
    try:
        ec2 = session.client('ec2')
        print(f'Releasing elastic IP address: {eip}')
        response = ec2.release_address(AllocationId=eip)
    except botocore.exception.ClientError as e:
        print("Check elastic IP address has been released AllocationId: {eip}")



def delete_subnet(session,subnet):
    if (subnet.state in ["deleted","deleting"]):
        return

    sub_id = subnet.id

    try:
        print("Deleting subnet {}".format(sub_id))
        ec2 = session.client('ec2')
        ec2.delete_subnet(SubnetId=sub_id)
        waiter = ec2.get_waiter('subnet_available')
        #waiter.wait(Filters=[
        #    { 'Name': 'state',     'Values': [ 'deleted' ] },
        #    { 'Name': 'subnet-id', 'Values': [ sub_id ] }
        #])
    except botocore.exceptions.WaiterError:
        pass
    except botocore.exceptions.ClientError as e:
        if (not subnet.state in ["deleted","deleting"]):
            print("Unable to delete subnet {}: ".format(sub_id) + str(e))



def delete_vpc(session, vpc_id):
    zzz = 2
    try:
        print("Deleting dependencies for VPC: {0}".format(vpc_id))
        ec2 = session.resource('ec2')
        vpc = ec2.Vpc(vpc_id)

        client = session.client('ec2')
        nats = client.describe_nat_gateways(Filter=[{"Name": "vpc-id", "Values": [ vpc_id ]}])
        nats = nats['NatGateways'] 
        for nat in nats:
            eip = nat['NatGatewayAddresses'][0]['AllocationId']
            delete_nat_gateway(session,nat)
            release_eip_address(session, eip)

        for instance in vpc.instances.all():
            print("Terminating instance: {0}".format(instance.id))
            response = instance.terminate()
            time.sleep(zzz)

        for interface in vpc.network_interfaces.all():
            print("Deleting network interface: {0}".format(interface.id))
            response = interface.delete()
            time.sleep(zzz)

        for subnet in vpc.subnets.all():
            delete_subnet(session, subnet)

        for sg in vpc.security_groups.all():
            if (sg.group_name != "default"):
               print("Deleting security group: {0}".format(sg.id))
               response = sg.delete()
               time.sleep(zzz)

        for igw in vpc.internet_gateways.all():
            print("Deleting internet gateway {}".format(igw.id))
            response = igw.detach_from_vpc(VpcId=vpc_id)
            time.sleep(zzz)
            response = igw.delete()
            time.sleep(zzz)

        for table in vpc.route_tables.all():
            print("Deleting route table {}".format(table.id))
            try:
                response = table.delete()
                time.sleep(zzz)
            except botocore.exceptions.ClientError:
                pass

        print("Deleting VPC {}".format(vpc_id))
        vpc.delete()
        time.sleep(zzz)

    except botocore.exceptions.ClientError as e:
        print("ERROR: " + str(e))




def pcluster_delete(session, label):
    try:
        print("Deleting cluster {0}".format(label))
        print("This will delete all AWS resources associated with this cluster, including storage.")
        response = input("Continue? [y/N] ")

        if (response != 'y' and response != 'yes'):
            return
        vpc_id = get_vpc_id(session, label)
        response = input("Delete VPC {0}? [y/N] ".format(vpc_id))

        if (response != 'y' and response != 'yes'):
            vpc_id = None

        cmd = "pcluster delete {0}".format(label);
        cmd = cmd.split()
        code = os.spawnvpe(os.P_WAIT, cmd[0], cmd, os.environ)
        if code == 127:
            sys.stderr.write('{0}: command not found\n'.format(cmd[0]))
        
        if (vpc_id):
            delete_vpc(session, vcp_id)

    except NameError:
        # Need to track this down
        pass
    except:
        print("Unable to delete cluster:", sys.exc_info()[0])




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

    except client.exceptions.EntityAlreadyExistsException:
       print("Using existing user account {0}".format(admin))
    except client.exceptions.NoSuchEntityException:
       print("Unable to configure admin user {0}".format(admin))
       sys.exit(1)
    except KeyError:
       print("Unable to configure access keys")
       sys.exit(1)



if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Manage QCloud clusters on AWS.');
    parser.add_argument("--file", dest="config_file", default="qcloud.config", 
        help="Defines an alternative config file.")

    parser.add_argument("--label", dest="label", default="qcloud",
        help="Provide and alternative name of the cluster stack")

    parser.add_argument("--config", dest="config",  action='store_true',
        help='Configure the cluster (default)')

    parser.add_argument("--start", dest="start",  action='store_true',
        help='Start the cluster')

    parser.add_argument("--stop", dest="stop",  action='store_true',
        help='Stop the cluster')

    parser.add_argument("--restart", dest="restart",  action='store_true',
        help='Restart a stopped cluster')

    parser.add_argument("--status", dest="info",  action='store_true',
        help='Get information on the cluster')

    parser.add_argument("--update", dest="update",  action='store_true',
        help='Update the cluster configuration')

    parser.add_argument("--delete", dest="delete",  action='store_true',
        help='Delete the cluster')

    parser.add_argument("--delete-vpc", dest="delete_vpc",  default=None, 
        help='Delete the VCP')

    parser.add_argument("--keygen", dest="keygen",  action='store_true',
        help="Generate ssh keys")

    parser.add_argument("--verbose", dest="verbose", action='store_true',
        help="Increase printout level")


    args, extra_args = parser.parse_known_args()

    verbose = args.verbose
    session = create_session()

    if args.keygen:
       create_account()

    elif args.start:
       pcluster_create(args.label, args.config_file)
       pcluster_start(args.label)

    elif args.info:
       pcluster_info(session,args.label)

    elif args.stop:
        pcluster_stop(args.label)

    elif args.update:
        pcluster_update(args.label, args.config_file)

    elif args.restart:
        pcluster_restart(args.label)

    elif args.delete:
       pcluster_delete(session,args.label)

    elif args.delete_vpc:
       delete_vpc(session,args.delete_vpc)

    elif args.config or len(sys.argv) == 1:
       configure_pcluster(session, args)

    else:
        print("Unrecognised argument:", sys.argv[1]);
        parser.print_help()
