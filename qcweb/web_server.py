import os
import sys
import ssl
import logging
import configparser
import urllib.request

import tornado.httpserver
import tornado.ioloop
import tornado.web

from job_manager import JobManager


class BaseHandler(tornado.web.RequestHandler):
    def initialize(self, authentication_url, job_manager):
        self.authentication_url = authentication_url
        self.job_manager = job_manager


    def validate_token(self, token):
        url = self.authentication_url + "/validate"
        req = urllib.request.Request(url)
        req.add_header("Qcloud-Token", token)
        res = urllib.request.urlopen(req)

        if (not res.headers.get("Qcloud-Server-Status") == "OK"):
           msg = res.headers.get("Qcloud-Server-Message")
           raise Exception(msg)

        return res.headers.get("Qcloud-Server-Userid")


    def get_job(self):
        token  = self.get_argument("cookie")
        jobid  = self.get_argument("jobid")
        userid = self.validate_token(token)
        job    = self.job_manager.get_job(jobid)

        # need to match job with user?
        if (not job.is_valid()):
           job.status = "INVALID"
           #raise Exception("Invalid jobid")

        return job

       

class Register(BaseHandler):
    def get(self):
        try:
            url = self.authentication_url + "/register"
            req = urllib.request.Request(url)
            res = urllib.request.urlopen(req)

            userid = res.headers["Qcloud-Server-Userid"]
            token  = res.headers["Qcloud-Token"]

            self.set_header("Qchemserv-Status", "OK")
            self.set_header("Qchemserv-Request", "register")
            self.set_header("Qchemserv-Cookie", token)

            logging.info("User added: " + userid)

        except Exception as e:
            msg = str(e);
            logging.error(msg)
            self.set_header("Qcloud-Server-Message", msg)



class SubmitJob(BaseHandler):
    def post(self):
        try:
            token  = self.get_argument("cookie")
            userid = self.validate_token(token)
            if (userid is None):
               raise tornado.web.HTTPError(401, log_message="Invalid token passed to submit")

            input = self.request.body.decode()
            job   = self.job_manager.submit_job(input)

            self.set_header("Qcloud-Server-Status", "OK")
            self.set_header("Qcloud-Server-Jobid", job.jobid)
            self.set_header("Qcloud-Server-Slurmid", job.slurmid)

            self.set_header("Qchemserv-Status", "OK")
            self.set_header("Qchemserv-Request", "submit")
            self.set_header("Qchemserv-Jobid", job.jobid)

            logging.info("Job %s submitted; UID=%s, JID=%s" % (job.slurmid, userid, job.jobid))

        except tornado.web.MissingArgumentError as e:
            msg = "Missing argument: " + str(e)
            self.set_header("Qcloud-Server-Message", msg)

        except Exception as e:
            msg = str(e);
            logging.error(msg)
            self.set_header("Qcloud-Server-Message", msg)




class ListFiles(BaseHandler):
    def prepare(self):
        try:
            job = self.get_job()
            if (job.status != "DONE"):
               raise Exception("Job not completed")

            filelist = job.files
            body = ''
            for f in filelist:
                body += ("%s\n" % f)
            self.write(body)

            self.set_header("Qcloud-Server-Status", "OK")
            self.set_header("Qcloud-Server-Jobid", job.jobid)

            self.set_header("Qchemserv-Status", "OK")
            self.set_header("Qchemserv-Request", "list")
            self.set_header("Qchemserv-Jobid", job.jobid)

            logging.info("Job list;      JID=%s" % (job.jobid))

        except tornado.web.MissingArgumentError as e:
            msg = "Missing argument: " + str(e)
            self.set_header("Qcloud-Server-Message", msg)

        except Exception as e:
            msg = str(e);
            logging.error(msg)
            self.set_header("Qcloud-Server-Message", msg)

    def get(self):
        pass
    
    def post(self):
        pass
 


class Download(BaseHandler):
    def prepare(self):
        try:
            job   = self.get_job()
            fname = self.get_argument("file")
            fpath = self.job_manager.get_job_filepath(job.jobid, fname)
            if (fpath is None):
               raise Exception("File not found " + fname)

            with open(fpath, 'r') as file:
               data = file.read()
            self.write(data)

            self.set_header("Qcloud-Server-Status", "OK")
            self.set_header("Qcloud-Server-Jobid", job.jobid)

            self.set_header("Qchemserv-Status", "OK")
            self.set_header("Qchemserv-Request", "download")
            self.set_header("Qchemserv-Jobid", job.jobid)

            logging.info("File download; JID=%s  file=%s " % (job.jobid, fname))

        except tornado.web.MissingArgumentError as e:
            msg = "Missing argument: " + str(e)
            self.set_header("Qcloud-Server-Message", msg)

        except Exception as e:
            msg = str(e);
            logging.error(msg)
            self.set_header("Qcloud-Server-Message", msg)

    def get(self):
        pass

    def post(self):
        pass



class JobStatus(BaseHandler):
    def prepare(self):
        try:
            job = self.get_job()

            self.set_header("Qcloud-Server-Status", "OK")
            self.set_header("Qcloud-Server-Jobid", job.jobid)
            self.set_header("Qcloud-Server-Jobstatus", job.status)

            self.set_header("Qchemserv-Status", "OK")
            self.set_header("Qchemserv-Request", "status")
            self.set_header("Qchemserv-Jobid", job.jobid)
            self.set_header("Qchemserv-Jobstatus", job.status)

            logging.info("Job status;    JID=%s  status=%s" % (job.jobid, job.status))

        except tornado.web.MissingArgumentError as e:
            msg = "Missing argument: " + str(e)
            self.set_header("Qcloud-Server-Message", msg)

        except Exception as e:
            msg = str(e);
            logging.error(msg)
            self.set_header("Qcloud-Server-Message", msg)

    def get(self):
        pass

    def post(self):
        pass



class DeleteJob(BaseHandler):
    def prepare(self):
        try:
            job = self.get_job()
           
            self.job_manager.delete_job(job.jobid)

            self.set_header("Qcloud-Server-Status", "OK")
            self.set_header("Qcloud-Server-Jobid", job.jobid)

            self.set_header("Qchemserv-Status", "OK")
            self.set_header("Qchemserv-Request", "delete")
            self.set_header("Qchemserv-Jobid", job.jobid)

            logging.info("Job deleted;   JID=%s" % (job.jobid))

        except tornado.web.MissingArgumentError as e:
            msg = "Missing argument: " + str(e)
            self.set_header("Qcloud-Server-Message", msg)

        except Exception as e:
            msg = str(e);
            logging.error(msg)
            self.set_header("Qcloud-Server-Message", msg)

    def get(self):
        pass
    
    def post(self):
        pass
    



class ComputeServer(tornado.web.Application):
    def __init__(self, config):
        job_manager = JobManager(config)

        # Authentication server details
        host = config.get("authentication", "host")
        port = config.get("authentication", "port")
        auth_url = "http://" + host + ":" + port

        args = dict( authentication_url = auth_url,
                     job_manager = job_manager )

        handlers = [ 
            (r"/register", Register,  args),
            (r"/submit",   SubmitJob, args),
            (r"/delete",   DeleteJob, args),  
            (r"/status",   JobStatus, args),
            (r"/list",     ListFiles, args),
            (r"/download", Download,  args),
        ]   

        settings = { 
            "debug" : config.get("authentication", "debug"),
        }   

        tornado.web.Application.__init__(self, handlers, **settings)




if __name__ == "__main__":

   logging.basicConfig(level=logging.DEBUG,
      format='%(asctime)s - %(levelname)-8s - %(message)s',
      datefmt='%d/%m/%Y %Hh%Mm%Ss')
   console = logging.StreamHandler(sys.stderr)

   cwd = os.getcwd()
   logging.info("Working directory  = %s" % cwd)
   logging.info("Python interpreter = %s" % sys.executable)

   config_file = sys.argv[1]
   if not os.path.isfile(config_file):
      logging.warn("Configuration file not found: '{0}'", config_file)
      sys.exit(1)

   logging.info("Reading configuration file: '{0}'".format(config_file))
   config = configparser.ConfigParser()
   config.read(config_file)

   ssl_context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
   path = os.path.dirname(os.path.realpath(__file__))
   cert = os.path.join(path, "certs","server.crt")
   key  = os.path.join(path, "certs","server.key")
   logging.info("Loading certificate files: '{0}', '{1}' ".format(cert, key))
   ssl_context.load_cert_chain(cert, key)

   server = tornado.httpserver.HTTPServer(ComputeServer(config), 
#      ssl_options = ssl_context
   )

   port = config.get("server", "port")
   server.listen(port)
   logging.info("QCloud server running on port %s" % port)

   tornado.ioloop.IOLoop.instance().start()
