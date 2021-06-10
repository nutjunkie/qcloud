import re
import uuid
import redis
import bcrypt
import logging

    
class UserManager():
    def __init__(self, config):

        host = config.get("redis","host")
        port = config.get("redis","port")
        logging.info("Connecting to user database redis//{0}:{1}".format(host,port))

        self.rdb = redis.StrictRedis(host=host, port=port, db=0, 
           charset='utf-8', decode_responses=True)

        salt = bytes(config.get("authentication", "salt").encode())
        #print("salt = ",salt, " ", type(salt))

        self.salt  = salt
        self.anon  = config.getboolean("authentication", "anon")
        self.admin = config.get("authentication", "admin_account")
        self.userid_re = re.compile("^[a-z0-9]{32}$")
        self.username_re = re.compile("^[a-zA-Z0-9_.-]+$")

        

    def add_user(self, user, password, authentication):
        if (self.anon):
           raise Exception("Invalid add user request for anonymous server")

        if (not self.authenticate_user(self.admin, authentication)):
           raise Exception("Invalid Admin password, permission denied")

        if (not self.username_is_valid(user)):
           raise Exception("Invalid username: " + user)

        userid = uuid.uuid4().hex
        hashpw = bcrypt.hashpw(password.encode('utf-8'), self.salt)
        hashpw = hashpw.decode('utf-8')
        self.rdb.hset("user:"+user, 'id', userid) 
        self.rdb.hset("user:"+user, 'pw', hashpw) 
        logging.info("Setting password hash for user " + user + " to " + hashpw)
        return userid



    def add_anonymous_user(self):
        if (not self.anon):
           raise Exception("Invalid add anonymous user request for server")

        userid = uuid.uuid4().hex
        self.rdb.hset("user:"+userid, 'id', userid) 
        return userid



    def delete_user(self, user, authentication):
        if (not self.user_exists(user)):
           raise Exception("Unknown user: " + user)
        if (user == self.admin or not self.authenticate_user(self.admin, authentication)):
           raise Exception("Invalid Admin password, permission denied")

        keys = list(self.rdb.hgetall("user:"+user).keys())
        self.rdb.hdel("user:"+user, *keys)



    def add_token(self, token, user):
        if (not self.user_exists(user)):
           raise Exception("Unknown user: " + user)

        self.rdb.rpush("tokens", token)
        self.rdb.dump("tokens")
        return True



    def username_is_valid(self, user):
        if (user == self.admin):
           return False
        elif (self.anon and self.userid_re.match(user)):
           return True
        elif (not self.anon and self.username_re.match(user)):
           return True
        return False



    def user_exists(self, user):
        if (user == self.admin):
           return True
        return self.username_is_valid(user) and self.rdb.hexists("user:"+user, 'id')



    def authenticate_user(self, user, password):
        if (self.anon):
           return self.user_exists(user)
        else:
           hashpw = bcrypt.hashpw(password.encode('utf-8'), self.salt)
           hashpw = hashpw.decode('utf-8')

           if (not self.user_exists(user)):
              raise Exception("Unknown user: " + user)
              
           return (self.rdb.hget("user:"+user, 'pw') == hashpw)



    def set_admin_password(self, password):
        userid = 1
        hashpw = bcrypt.hashpw(password.encode('utf-8'), self.salt)
        hashpw = hashpw.decode('utf-8')
        self.rdb.hset("user:"+self.admin, 'id', userid)
        self.rdb.hset("user:"+self.admin, 'pw', hashpw)
        return userid
