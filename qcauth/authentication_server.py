import os
import jwt
import sys
import ssl
import string
import base64
import random
import logging
import datetime
import configparser

import tornado.httpserver
import tornado.ioloop
import tornado.web

import user_manager



def generate_tornado_cookie()
    """Generates a cookie used for encryption by tornado"""
    return base64.b64encode(uuid.uuid4().bytes + uuid.uuid4().bytes)


def random_string(len):
    """Generates a random string of letters and numbers length len"""
    letters = string.ascii_letters + string.digits
    return ''.join(random.choice(letters) for i in range(len))



def random_key():
    """Generates a standardised JWT key"""
    block_size = 8;
    key = random_string(block_size)
    for i in range(block_size-1):
        key += "-" + random_string(block_size)
    return key 



def generate_jwt(userid, exp, code):
    payload = {}
    payload['userid'] = userid

    if (userid == 1):  
       payload['exp'] =  datetime.datetime.utcnow() 
       payload['exp'] += datetime.timedelta(seconds=1)
    elif (exp != 0):
       payload['exp'] =  datetime.datetime.utcnow() 
       payload['exp'] += datetime.timedelta(seconds=int(exp))

    token = jwt.encode(payload, code, algorithm='HS256')

    return token.decode('utf-8')



class BaseHandler(tornado.web.RequestHandler):
    def initialize(self, jwt_code, jwt_expiry, user_manager):
        self.jwt_code     = jwt_code
        self.jwt_expiry   = jwt_expiry
        self.user_manager = user_manager

    def dump_headers(self):
        hdrs = self.request.headers 
        for (k,v) in sorted(hdrs.get_all()):
            print("Request Header> %s:  %s" % (k,v))



class AddUser(BaseHandler):
    def get(self):
        try:
            user   = self.request.headers["Qcloud-Client-User"]
            passwd = self.request.headers["Qcloud-Client-Password"]
            auth   = self.request.headers["Qcloud-Client-Authorisation"]
            userid = self.user_manager.add_user(user, passwd, auth)
            token  = generate_jwt(userid, self.jwt_expiry, self.jwt_code)

            self.set_header("Qcloud-Server-Status", "OK")
            self.set_header("Qcloud-Server-Userid", userid) 
            self.set_header("Qcloud-Token", token)
            logging.info("User added: " + user)

        except KeyError as e:
            msg = "Missing header: " + str(e)
            self.set_header("Qcloud-Server-Message", msg)

        except Exception as e:
            msg = str(e);
            logging.error(msg)
            self.set_header("Qcloud-Server-Message", msg)



class AddAnonymousUser(BaseHandler):
    def get(self):
        try:
            userid = self.user_manager.add_anonymous_user()
            token  = generate_jwt(userid, 0, self.jwt_code)

            self.set_header("Qcloud-Server-Status", "OK")
            self.set_header("Qcloud-Server-Userid", userid) 
            self.set_header("Qcloud-Token", token)
            logging.info('User added: ' + userid)

        except Exception as e:
            msg = str(e);
            logging.error(msg)
            self.set_header("Qcloud-Server-Message", msg)



class DeleteUser(BaseHandler):
    def get(self):
        try:
            user   = self.request.headers["Qcloud-Client-User"]
            auth   = self.request.headers["Qcloud-Client-Authorisation"]
            userid = self.user_manager.delete_user(user, auth)

            self.set_header("Qcloud-Server-Status", "OK")
            logging.info('User deleted: ' + user)

        except KeyError as e:
            msg = "Missing header: " + str(e)
            self.set_header("Qcloud-Server-Message", msg)

        except Exception as e:
            msg = str(e);
            logging.error(msg)
            self.set_header("Qcloud-Server-Message", msg)



class RequestToken(BaseHandler):
    def get(self):
        try:
            user   = self.request.headers["Qcloud-Client-User"]
            passwd = self.request.headers["Qcloud-Client-Password"]

            if (not self.user_manager.authenticate_user(user, passwd)):
               raise Exception("Invalid password")

            userid = str(self.user_manager.rdb.hget(user,'id'))
            token  = generate_jwt(userid, self.jwt_expiry, self.jwt_code)

            self.set_header("Qcloud-Server-Status", "OK")
            self.set_header("Qcloud-Server-Userid", userid) 
            self.set_header("Qcloud-Token", token) 
            logging.info("Token issued for user " + user + ":" + token)

        except KeyError as e:
            msg = "Missing header: " + str(e)
            self.set_header("Qcloud-Server-Message", msg)

        except Exception as e:
            msg = str(e);
            logging.error(msg)
            self.set_header("Qcloud-Server-Message", msg)



class ValidateToken(BaseHandler):
    def get(self):
        try: 
            token = self.request.headers["Qcloud-Token"]
            logging.info("validating token: " + token)
            logging.info("    with key:     " + self.jwt_code)
            decoded = jwt.decode(token, self.jwt_code, algorithm='HS256')
            self.set_header("Qcloud-Server-Status", "OK")
            self.set_header("Qcloud-Server-Userid", decoded['userid'])
            logging.info("    user decoded: " + decoded['userid'])

        except jwt.ExpiredSignatureError:
            msg = "JWT signature expired"
            self.set_header("Qcloud-Server-Message", msg)
            logging.info(msg)
   
        except jwt.DecodeError:
            msg = "JWT failed validation"
            self.set_header("Qcloud-Server-Message", msg)
            logging.error(msg)

        except jwt.InvalidTokenError:
            msg = "JWT invalid token"
            self.set_header("Qcloud-Server-Message", msg)
            logging.error(msg)

        except KeyError as e:
            msg = "Missing header: " + str(e)
            self.set_header("Qcloud-Server-Message", msg)
            logging.error(msg)

        except Exception as e:
            msg = str(e);
            self.set_header("Qcloud-Server-Message", msg)
            logging.error(msg)



class AuthenticationServer(tornado.web.Application):
    def __init__(self, config):

		# A random key generated here will invalidate all previously issued
		# JWTs.  This should NOT be a random key if the server is anonymous as
		# existing users will no longer be able to validate their tokens.
        jwt_code   = config.get("authentication", "jwt_code")
        jwt_expiry = config.get("authentication", "jwt_expiry")

#       if (not config.getboolean("authentication","anon")):
#          jwt_code = random_key()

        logging.info("JWT key:    " + jwt_code)
        logging.info("JWT expiry: " + jwt_expiry)

        usr_man = user_manager.UserManager(config)
        usr_man.set_admin_password(config.get("authentication", "admin_password"))

        args = dict(jwt_code     = jwt_code, 
                    jwt_expiry   = jwt_expiry,
                    user_manager = usr_man)

        handlers = [
            (r"/token",    RequestToken,     args),
            (r"/adduser",  AddUser,          args),
            (r"/register", AddAnonymousUser, args),
            (r"/validate", ValidateToken,    args),
        ]

        settings = {
            "debug"        : config.get("authentication", "debug"),
            "cookie_secret": config.get("authentication", "cookie"),
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

   server = tornado.httpserver.HTTPServer(AuthenticationServer(config), 
#     ssl_options = ssl_context
   )
   port = config.get("authentication", "port")
   server.listen(port)
   if (config.getboolean("authentication","anon")):
      logging.info("Anonymous authentication server running on port %s" % port)
   else:
      logging.info("Authentication server running on port %s" % port)

   tornado.ioloop.IOLoop.instance().start()
