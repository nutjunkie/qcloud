import unittest
from rqconn_pbs import RQConnPBS

class RQConnPBSTest(unittest.TestCase):
    def setUp(self):
        pass

    def test_conn(self):
        conn = RQConnPBS("fluffy.usc.edu", 53142, "epif", 10)
        conn.update()

    def test_submit(self):
        conn = RQConnPBS("fluffy.usc.edu", 53142, "epif", 10)
        conn.submit_job("asdfasdf", "asdf")

if __name__ == '__main__':
    unittest.main()
