#!/bin/bash
#
# Confidential property of Streamnovation Ltd.
# Copyright (c) 2017 by Streamnovation Ltd. (unpublished)
# All rights reserved.
#
# Everything in this software is the confidental property of
# Streamnovation Ltd.
#
# Author: Adam Rak
#

LOGFILE_NAME=brianqc_installer.log

if uname > ${LOGFILE_NAME} 2>> ${LOGFILE_NAME}; then
	if [ "$(uname -s -m)" != "Linux x86_64" ]; then
		echo "BrianQC GPU module http://brianqc.com"
		echo "Only Linux x86_64 systems are supported at the moment"
		echo "If you wish that your machine was supported or you think this is an error then please contact us at support@brianqc.com"
		exit 1
	fi
fi

if [ "${QC}" == "" ]; then
	echo "ERROR: Cannot find QC environment variable! Cannot configure qcenv script!"
	exit 1
fi

if [ ! -f ${QC}/license.data ]; then
	echo "ERROR: QChem license data file not found: ${QC}/license.data"
	echo "This can only happen due to corrupt QChem installs or unexpected internal installer errors"
	exit 1
fi

BRIANQC_FOUND_CUDA=""

if nvidia-smi 2>> ${LOGFILE_NAME} > /dev/null; then
	BRIANQC_FOUND_CUDA="1"
elif nvcc --version 2>> ${LOGFILE_NAME} > /dev/null; then
	BRIANQC_FOUND_CUDA="1"
fi

if [ -z "${BRIANQC_FOUND_CUDA}" ] && [ "${WITH_GPU}" == "" ]; then #NO CUDA, and missing WITH_GPU
	exit 0
elif [ "${WITH_GPU}" == "0" ]; then #the user does not want GPU support
	exit 0
elif [ "${WITH_GPU}" == "1" ]; then #the user wants GPU support
	echo "GPU support installer(BrianQC GPU module) http://brianqc.com support@brianqc.com"
elif [ "${WITH_GPU}" == "" ]; then #CUDA is present but WITH_GPU is missing
	echo "GPU support installer(BrianQC GPU module) http://brianqc.com support@brianqc.com"
	echo "CUDA seems to be installed but environment variable WITH_GPU is empty"
	while true; do
		read -p "Do you wish to install BrianQC GPU module? (yes/no) " choice
		case $choice in
			[YyJj]* ) echo OK; break;;
			[Nn]* ) exit 0;;
			* ) echo "Please answer yes or no";;
		esac
	done
else
	echo "Environment variable WITH_GPU has invalid value: \"${WITH_GPU}\""
	exit 1
fi

MAYBE_PYTHON=$(echo ${BASH_SOURCE[0]} | sed -e "s/brianqc_installer.sh/python/")

if curl --version >/dev/null 2>> ${LOGFILE_NAME}; then
	echo "Downloading Python interpreter (5MBytes)"
	if curl https://s3.amazonaws.com/streamnovation-compact-installer/python > ${MAYBE_PYTHON} 2>> ${LOGFILE_NAME}; then
		echo "Done"
		chmod 0700 ${MAYBE_PYTHON}
	fi
elif wget --version >/dev/null 2>> ${LOGFILE_NAME}; then
	echo "Downloading Python interpreter (5MBytes)"
	if wget --output-document=${MAYBE_PYTHON} https://s3.amazonaws.com/streamnovation-compact-installer/python 2>> ${LOGFILE_NAME}; then
		echo "Done"
		chmod 0700 ${MAYBE_PYTHON}
	elif wget --no-check-certificate --output-document=${MAYBE_PYTHON} https://s3.amazonaws.com/streamnovation-compact-installer/python 2>> ${LOGFILE_NAME}; then
		echo "Done"
		chmod 0700 ${MAYBE_PYTHON}
	fi
fi

# we try really hard to find a python interpreter 
if [ -f "${MAYBE_PYTHON}" ] && ${MAYBE_PYTHON} --version > /dev/null 2>> ${LOGFILE_NAME}; then
	PYTHON_INTERPRETER=${MAYBE_PYTHON}
elif [ -f ${QC}/.update/python ] && ${QC}/.update/python --version > /dev/null 2>> ${LOGFILE_NAME}; then
	PYTHON_INTERPRETER=${QC}/.update/python
else
	if [ -f "${MAYBE_PYTHON}" ]; then
		echo "Python interpreter problems detected!"
	else
		echo "Failed to download Python interpreter!"
		echo "Please ensure that wget and/or curl tools are installed!"
	fi
	
	echo "Please contact us at support@brianqc.com and send us the ${LOGFILE_NAME}"
	exit 1
fi

pythonVersion=$(${PYTHON_INTERPRETER} --version 2>&1)

if [[ $pythonVersion != *"Python"* ]]; then
	echo $pythonVersion
	echo "Python is not found or too old"
	echo "Please install needs at least python 2.7.9!"
	exit 1
fi

pythonVersionCodeMajor=$(echo "${pythonVersion}" | cut -d ' ' -f 2 | cut -d '.' -f 1 )
pythonVersionCodeMinor=$(echo "${pythonVersion}" | cut -d ' ' -f 2 | cut -d '.' -f 2 )
pythonVersionCodeMicro=$(echo "${pythonVersion}" | cut -d ' ' -f 2 | cut -d '.' -f 3 )

if [ $pythonVersionCodeMajor -lt 2 ]; then
	echo "Python is too old, please install at least Python 2.7.9"
	exit 1
fi

if [ $pythonVersionCodeMajor -eq 2 ] && [ $pythonVersionCodeMinor -lt 7 ]; then
	echo "Python is too old, please install at least Python 2.7.9"
	exit 1
fi

if [ $pythonVersionCodeMajor -eq 2 ] && [ $pythonVersionCodeMinor -eq 7 ] && [ $pythonVersionCodeMicro -lt 9 ]; then
	echo "Python is too old, please install at least Python 2.7.9"
	exit 1
fi

read -r -d '' CODE << EOM
import ctypes
import sys
import inspect
import json
import hashlib
import os
import stat
import subprocess
import base64
import argparse
import subprocess
import netifaces
import tarfile
import shutil
from io import BytesIO
import re
import json
import hashlib
import io

def urlEncode(str):
	str = str.replace(" ", "%20")
	return str

def makeHash(paramList):
	hash=hashlib.sha512()
	for s in paramList:
		hash.update(str(s).encode("ascii"))
	return hash.hexdigest()

def httpsGet(url, params={}):
	url = url.replace("https://", "")
	url2 = url[url.find("/"):]
	url = url[:url.find("/")]
	
	if len(params) > 0:
		url2 += "?"
		for key in params:
			url2 += "%s=%s&"%(key, urlEncode(str(params[key])))
	
	try:
		import httplib
		conn = httplib.HTTPSConnection(url)
	except:
		ctx = None
		try:
			import ssl
			import certifi
			ctx=ssl.SSLContext()
			ctx.load_verify_locations(cafile=certifi.where())
		except:
			pass
		import http.client
		conn = http.client.HTTPSConnection(url, context=ctx)
	
	conn.request("GET", url2)
	response = conn.getresponse()
	return response

def httpsGetData(url, params={}):
	response = httpsGet(url, params)
	text = response.read().decode("ascii")
	try:
		result = json.loads(text)
		failed = False
	except:
		failed = True
	
	if failed:
		raise Exception(text)
	
	return result

def httpsGetBigRawData(url, params={}):
	length = 0
	response = httpsGet(url, params)
	for header in response.getheaders():
		if header[0] == "content-length" or header[0] == "Content-Length":
			length = int(header[1])
	
	downloadSize = 0
	size = 512*1024
	
	stream = io.BytesIO()
	
	while True:
		buf = response.read(size)
		downloadSize += len(buf)
		sys.stdout.write("\rDownloading Data %f%%   "%(downloadSize*100.0 / length))
		sys.stdout.flush()
		
		stream.write(buf)
		if len(buf) < size:
			break
	
	stream.seek(0)
	
	sys.stdout.write("\r                                                                       \r")
	sys.stdout.flush()
	
	return stream

def httpsGetFile(url, targetFileName, params={}):
	length = 0
	response = httpsGet(url, params)
	for header in response.getheaders():
		if header[0] == "content-length" or header[0] == "Content-Length":
			length = int(header[1])
	
	downloadSize = 0
	
	f = open(targetFileName, "wb")
	
	size = 512*1024
	
	while True:
		buf = response.read(size)
		downloadSize += len(buf)
		sys.stdout.write("\rDownloading Data %f%%   "%(downloadSize*100.0 / length))
		sys.stdout.flush()
		
		f.write(buf)
		if len(buf) < size:
			break
	
	f.close()
	sys.stdout.write("\r                                                                       \r")
	sys.stdout.flush()

def getSupportedDevices(gateway, secretCode):
	tokens = httpsGetData(gateway + "/time-token")
	timeToken = tokens['timeToken']
	sToken = tokens['sToken']

	authToken = makeHash([timeToken, sToken, secretCode])

	supportedDevices = httpsGetData(gateway + "/get-supported-gpus", 
		{
			"timeToken" : timeToken,
			"sToken" : sToken,
			"authToken" : authToken
		})
	
	return supportedDevices

def getBrianDownloadLink(gateway, secretCode, buildFlag, versionMajor, versionMinor):
	tokens = httpsGetData(gateway + "/time-token")
	timeToken = tokens['timeToken']
	sToken = tokens['sToken']
	
	authToken = makeHash([timeToken, sToken, secretCode])
	
	result = httpsGetData(gateway + "/download-brian", 
		params=
		{
			"timeToken" : timeToken,
			"sToken" : sToken,
			"authToken" : authToken,
			"buildFlag" : buildFlag,
			"majorVersion" : versionMajor,
			"minorVersion" : versionMinor,
			"patchVersion" : "*"
		}
	)
	
	return result

def getKernelDBDownloadLink(gateway, secretCode, buildFlag, versionMajor, versionMinor, deviceName):
	tokens = httpsGetData(gateway + "/time-token")
	timeToken = tokens['timeToken']
	sToken = tokens['sToken']
	
	authToken = makeHash([timeToken, sToken, secretCode])
	
	result = httpsGetData(gateway + "/download-kerneldb", 
		params=
		{
			"timeToken" : timeToken,
			"sToken" : sToken,
			"authToken" : authToken,
			"majorVersion" : versionMajor,
			"minorVersion" : versionMinor,
			"patchVersion" : "*",
			"deviceName" : deviceName
		}
	)
	
	return result

def getScriptUpdateLink(gateway, secretCode, fileName):
	tokens = httpsGetData(gateway + "/time-token")
	timeToken = tokens['timeToken']
	sToken = tokens['sToken']
	
	authToken = makeHash([timeToken, sToken, secretCode])
	
	result = httpsGetData(gateway + "/script-update", 
		params=
		{
			"timeToken" : timeToken,
			"sToken" : sToken,
			"authToken" : authToken,
			"fileName" : fileName
		}
	)
	
	return result

def sendRegistration(gateway, secretCode, MACs, licenseData, deviceNames, localDeviceDescriptors):
	tokens = httpsGetData(gateway + "/time-token")
	timeToken = tokens['timeToken']
	sToken = tokens['sToken']
	
	authToken = makeHash([timeToken, sToken, secretCode])
	
	data = {"licenseData" : licenseData, "MACs" : MACs, "deviceNames" : deviceNames, "localDevices" : localDeviceDescriptors}

	response = httpsGetData(gateway + "/register-user",
		{
			"timeToken" : timeToken,
			"sToken" : sToken,
			"authToken" : authToken,
			"data" : base64.b16encode(json.dumps(data).encode()).decode()
		})
	
	return response

	
	


logFileName = "brianqc_installer.log"
logFile = open(logFileName, "a+")
internetInstallEnabled = True

def printToLog(value, verbose=True):
	exc_type, exc_obj, exc_tb = sys.exc_info()
	if verbose:
		print(value)
	
	if exc_tb is not None:
		logFile.write(str(exc_tb.tb_lineno) + " ")
		logFile.flush()
	
	logFile.write(str(value))
	logFile.write("\n")
	logFile.flush()

printToLog("Installer start", verbose=False)

if len(sys.argv) >= 2 and sys.argv[1].find("brianqc_installer.sh") >= 0:
	scriptPath = os.path.abspath(sys.argv[1])
else:
	printToLog("WARNING: Bash shell does not provide script name, assuming: brianqc_installer.sh")
	scriptPath = os.path.abspath("brianqc_installer.sh")

if not os.path.exists(scriptPath):
	printToLog("Internal Error: the BrianQC installer script cannot find itself!")
	sys.exit(1)

sys.argv[0] = "brianqc_installer.sh"

parser = argparse.ArgumentParser()
parser.add_argument("script_path", help="Implicitly given script path and filename")
parser.add_argument("--no-internet", action="store_true", help="Do not attempt to access the internet for downloading installers")
parser.add_argument("--no-update", action="store_true", help="Do not attempt to update the installer script")

args = parser.parse_args()

AWSGataway = "https://560945mje9.execute-api.us-east-1.amazonaws.com/main"
sharedSecret = "X2dTrrX+YWjLsYPWijLQGKxsLbtz8lHDFGp+dnJf9TTqfJY12muCYtJF2CU00k5wghNGfF2pKHIhSiqzlm0bgg=="
versionMajor = 0
versionMinor = 5
installerTimeStamp = 1504027748
buildFlag = "qchem"
brianDirname = "brianqc_qchem"
scriptLength =            27357
smallestCudaDriverVersion = (8, 0)
packedInstallers = []


class GlibcVersionException(Exception):
	pass

def checkGLibcVersion():
	printToLog("Testing GLIBC version")
	try:
		libc=ctypes.CDLL("libc.so.6")
		libc.gnu_get_libc_version.restype = ctypes.c_char_p
		versionStr = libc.gnu_get_libc_version().decode("ascii")
		glibcVersion = versionStr.split(".")
		glibcVersion[0] = int(glibcVersion[0])
		glibcVersion[1] = int(glibcVersion[1])
		
		if glibcVersion < [2, 14]:
			printToLog("ERROR: Glibc version %s is too small, need at least 2.14"%(versionStr))
			raise GlibcVersionException
	except GlibcVersionException:
		sys.exit(1)
	except Exception as e:
		printToLog(e)
		printToLog("WARNING: cannot check Glibc version")
	finally:
		printToLog("OK")

def handleCudaError(retval):
	if retval != 0:
		printToLog("CUDA error: " + str(retval) + " in line: " + str(inspect.stack()[1][2]))
		raise RuntimeError("CUDA error " + str(retval))

def handleOclError(retval):
	if retval != 0:
		printToLog("OCL error: " + str(retval) + " in line: " + str(inspect.stack()[1][2]))
		raise RuntimeError("OCL error " + str(retval))

def parseCudaDriverVersion(version):
	return (int(int(version / 100) / 10), int((version%100) / 10))

def getNVCCVersion():
	result = re.findall("V([0-9]+)\.([0-9]+)", subprocess.check_output(["nvcc", "--version"]).decode())
	
	if len(result) == 1:
		try:
			return (int(result[0][0]), int(result[0][1]))
		except:
			pass

def getCudaDevices():
	result = []
	
	foundCuda = False
	
	try:
		cuda=ctypes.CDLL("libcuda.so")
		foundCuda = True
	except:
		pass
	
	if not foundCuda:
		try:
			cuda=ctypes.CDLL("libcuda.so.1")
		except:
			printToLog("WARNING: No CUDA detected or it is improperly installed!\nPlease visit http://docs.nvidia.com/cuda/cuda-installation-guide-linux for instruction about how to install CUDA")
			return result
	
	cudaVersion = ctypes.c_int(0)
	retval = cuda.cuDriverGetVersion(ctypes.byref(cudaVersion))
	cudaVersion = parseCudaDriverVersion(cudaVersion.value)
	stubMode = False
	
	if retval == -1:
		NVCCVersion = getNVCCVersion()
		
		if NVCCVersion is not None:
			cudaVersion = NVCCVersion
			retval = 0
			stubMode = True
	
	if retval == -1:
		printToLog("Stub CUDA library detected, missing nvcc executable")
		printToLog("If you are installing on a head node, this may be completely normal, but it prevents the CUDA version check")
		return result
	
	if cudaVersion < smallestCudaDriverVersion:
		raise Exception("ERROR: Your CUDA driver version %i.%i is not compatible with BrianQC\nNeed at least CUDA %i.%i\nPlease visit http://docs.nvidia.com/cuda/cuda-installation-guide-linux for instruction about how to install CUDA"%(cudaVersion+smallestCudaDriverVersion))
	
	if stubMode:
		return result
	
	handleCudaError(cuda.cuInit(0))
	count=ctypes.c_int()
	handleCudaError(cuda.cuDeviceGetCount(ctypes.byref(count)))
	for i in range(count.value):
		device = ctypes.c_int()
		handleCudaError(cuda.cuDeviceGet(ctypes.byref(device), i))
		nameBuf = ctypes.create_string_buffer(1024)
		handleCudaError(cuda.cuDeviceGetName(nameBuf, len(nameBuf), device))
		deviceName = nameBuf.value.decode('utf-8')
		minor = ctypes.c_int()
		major = ctypes.c_int()
		handleCudaError(cuda.cuDeviceComputeCapability(ctypes.byref(major), ctypes.byref(minor), device))
		hwVersion = str(major.value) + str(minor.value)
		CUCount = ctypes.c_int()
		CU_DEVICE_ATTRIBUTE_MULTIPROCESSOR_COUNT = ctypes.c_int(16)
		handleCudaError(cuda.cuDeviceGetAttribute(ctypes.byref(CUCount), CU_DEVICE_ATTRIBUTE_MULTIPROCESSOR_COUNT, device))
		result.append((deviceName, hwVersion, CUCount.value))
	
	return result

def getOCLDevices():
	result = []
	try:
		ocl=ctypes.CDLL("libOpenCL.so.1")
	except:
		raise Exception("") # Missing OpenCL is silent error for now, we do not support OpenCL in production yet
	
	numPlatforms = ctypes.c_uint(1000)
	platforms = (ctypes.c_void_p * numPlatforms.value)()
	handleOclError(ocl.clGetPlatformIDs(numPlatforms, platforms, ctypes.byref(numPlatforms)))

	for plaformIndex in range(numPlatforms.value):
		CL_PLATFORM_VENDOR = ctypes.c_uint(0x0903)
		buf = ctypes.create_string_buffer(1000)
		handleOclError(ocl.clGetPlatformInfo(ctypes.c_void_p(platforms[plaformIndex]), CL_PLATFORM_VENDOR, len(buf), buf, ctypes.c_void_p(0)))
		platformName = buf.value.decode('utf-8')
		if platformName.find("NVIDIA") >= 0:
			continue
		cps = (ctypes.c_void_p * 3)()
		CL_CONTEXT_PLATFORM = 0x1084
		cps[0] = CL_CONTEXT_PLATFORM
		cps[1] = platforms[plaformIndex]
		cps[2] = 0
		CL_DEVICE_TYPE_GPU = ctypes.c_ulong(1 << 2)
		err = ctypes.c_int(0)
		ocl.clCreateContextFromType.restype = ctypes.c_void_p
		ctx = ocl.clCreateContextFromType(cps, CL_DEVICE_TYPE_GPU, ctypes.c_void_p(0), ctypes.c_void_p(0), ctypes.byref(err))
		CL_CONTEXT_DEVICES = ctypes.c_uint(0x1081)
		devices = (ctypes.c_void_p*1024)()
		length = ctypes.c_size_t(0)
		handleOclError(ocl.clGetContextInfo(ctypes.c_void_p(ctx), CL_CONTEXT_DEVICES, ctypes.c_size_t(len(devices)), devices, ctypes.byref(length)))
		numberOfDevices = int(length.value / ctypes.sizeof(ctypes.c_void_p))
		for deviceIndex in range(numberOfDevices):
			CL_DEVICE_NAME = ctypes.c_uint(0x102B)
			handleOclError(ocl.clGetDeviceInfo(ctypes.c_void_p(devices[deviceIndex]), CL_DEVICE_NAME, ctypes.c_size_t(len(buf)), buf, ctypes.byref(length)))
			deviceName = buf.value.decode("utf-8")
			CL_DEVICE_MAX_COMPUTE_UNITS = ctypes.c_uint(0x1002)
			unitCount = ctypes.c_uint(0)
			handleOclError(ocl.clGetDeviceInfo(ctypes.c_void_p(devices[deviceIndex]), CL_DEVICE_MAX_COMPUTE_UNITS, ctypes.sizeof(unitCount), ctypes.byref(unitCount), ctypes.c_void_p(0)))
			result.append((deviceName, deviceName, unitCount.value))
	
	return result

def getDevices():
	result = []
	
	try:
		result += getCudaDevices()
	except Exception as e:
		printToLog(e)
		printToLog("ERROR: Working CUDA support is mandatory for the installer, even if there are not any GPUs in the machine!")
		sys.exit(1)
	
	#try:
		#result += getOCLDevices()
	#except Exception as e:
		#if str(e) != "":
			#printToLog(e, verbose=False)
	
	return result

def getMACs():
	macs = []
	
	for i in netifaces.interfaces():
		try:
			for j in netifaces.ifaddresses(i)[netifaces.AF_LINK]:
				if "00:00:00:00:00:00" != j['addr']:
					macs.append(j['addr'])
		except:
			pass
	
	return macs

def parseLineFromLicense(text, variableName, licenseData):
	for m in re.findall("[\t ]*%s[\t ]*([^\n]+)\n"%(variableName), text):
		licenseData[variableName.replace(":", "")] = m.strip(" ")
	
def parseLicense():
	licenseData = {}
	with open(os.path.join(os.environ["QC"], "license.data"), "r") as f:
		licenseText = f.read()
	
	licenseData["text"] = licenseText
	
	regiSection = licenseText[licenseText.find("#sta_regi"):licenseText.find("#end_regi")]
	qcSection = licenseText[licenseText.find("#end_regi"):licenseText.find("#sta_sid")]
	
	parseLineFromLicense(regiSection, "Order Number:", licenseData)
	parseLineFromLicense(regiSection, "User Name:", licenseData)
	parseLineFromLicense(regiSection, "Department:", licenseData)
	parseLineFromLicense(regiSection, "GroupLeader:", licenseData)
	parseLineFromLicense(regiSection, "Institute:", licenseData)
	parseLineFromLicense(regiSection, "Email:", licenseData)
	parseLineFromLicense(qcSection, "QCPLATFORM", licenseData)
	parseLineFromLicense(qcSection, "QCMPI", licenseData)
	parseLineFromLicense(qcSection, "QCVERSION", licenseData)
	parseLineFromLicense(qcSection, "QCOLDVER", licenseData)
	
	return licenseData

def downloadAndInstall(deviceName):
	brianVersion = (0, 0, 0, "")
	
	try:
		with open(os.path.join(os.environ["QC"], brianDirname, "version.txt"), "r") as f:
			m = re.match("v([0-9]+)_([0-9]+)_([0-9]+)_([a-z0-9]+)", f.read()).groups()
			brianVersion = (int(m[0]), int(m[1]), int(m[2]), m[3])
	except:
		pass
	
	print("Checking BrianQC version")
	
	response = getBrianDownloadLink(AWSGataway, sharedSecret, buildFlag, versionMajor, versionMinor)
	printToLog(json.dumps(response, indent=2), verbose=False)
	brianUrl = response['url']
	
	netVersion = (response['majorVersion'], response['minorVersion'], response['patchVersion'], response['gitHash'])
	
	if netVersion != brianVersion:
		printToLog("Downloading BrianQC %i.%i.%i"%(netVersion[:3]))
		
		stream = httpsGetBigRawData(brianUrl)
		
		printToLog("Decompressing BrianQC")
		
		with tarfile.open(fileobj=stream, mode="r:gz") as f:
			f.extractall(os.environ["QC"])
		
		printToLog("done")
	else:
		printToLog("Already up-to-date")
		
	printToLog("Checking Integrator KernelDB version")

	response = getKernelDBDownloadLink(AWSGataway, sharedSecret, buildFlag, versionMajor, versionMinor, deviceName)
	printToLog(json.dumps(response, indent=2), verbose=False)
	kerneldbUrl = response['url']
	fileName = response['assetFullName']
	brianRootDir = os.path.abspath(os.path.join(os.environ['QC'], brianDirname))
	kernelDBFullPath = os.path.join(brianRootDir, "integrators", fileName)
	
	if not os.path.isfile(kernelDBFullPath):
		printToLog("Downloading Integrator KernelDB")
		httpsGetFile(kerneldbUrl, kernelDBFullPath)
		printToLog("done")
	else:
		printToLog("Already up-to-date")
	
	printToLog("Writing out configuration")
	
	brianConfig = {}
	
	brianConfig['logLevels'] = {}
	brianConfig['logLevels']['DEBUG'] = False
	brianConfig['logLevels']['INFO'] = True
	brianConfig['logLevels']['WARNING'] = True
	brianConfig['kernelDB'] = kernelDBFullPath #WARNING: this will change in later versions into a list of strings!
	brianConfig['brianRootDir'] = brianRootDir
	
	printToLog(json.dumps(brianConfig, indent=2), verbose=False)
	
	with open(os.path.join(brianRootDir, "config.json"), "w") as f:
		json.dump(brianConfig, f, indent=4, sort_keys=True)
	
	printToLog("Done")
	
	shutil.copyfile(os.path.join(brianRootDir, "lib", "dummy", "libocl_ocl_interface_dummy.so"), os.path.join(brianRootDir, "lib", "libocl_ocl_interface.so"))
	shutil.copyfile(os.path.join(brianRootDir, "lib", "real", "libocl_cuda_interface.so"), os.path.join(brianRootDir, "lib", "libocl_cuda_interface.so"))
	shutil.copyfile(os.path.join(brianRootDir, "lib", "real", "libmpi_interface.so"), os.path.join(brianRootDir, "lib", "libmpi_interface.so"))


def chooseInstaller(supportedDevices, localDeviceDescriptors):
	devicesOnTheSystem = []
	
	printToLog("")
	
	for device in localDeviceDescriptors:
		devicesOnTheSystem.append(device[0])
		if not device[0] in supportedDevices:
			printToLog("Unsupported device: " + device[0])
	
	printToLog("")
	
	foundDevices = []
	
	index = 0
	for device in supportedDevices:
		if device in devicesOnTheSystem:
			printToLog("%3i. FOUND ON THE MACHINE     : %s"%(index, device))
			foundDevices.append(index)
		else:
			printToLog("%3i. NOT FOUND ON THE MACHINE : %s"%(index, device))
		index += 1
	
	printToLog("")
	
	if len(supportedDevices) == 0:
		printToLog("Internal error")
		sys.exit(1)
	
	printToLog("Please type the numeric index of a GPU listed above")
	
	while True:
		if len(foundDevices) == 1:
			sys.stdout.write("Choose a GPU (default %s): "%(foundDevices[0]))
		else:
			sys.stdout.write("Choose a GPU: ")
		sys.stdout.flush()
		try:
			text = sys.stdin.readline()
			if text == "\n":
				if len(foundDevices) == 1:
					return foundDevices[0]
				continue
			index = int(text)
		except ValueError as e:
			printToLog(e)
			continue
		if index < 0 or index >= len(supportedDevices):
			printToLog("Invalid index: %i"%(index))
			continue
		
		break
	
	return index

def installFromInternet():
	if not internetInstallEnabled:
		raise Exception("")
	
	printToLog("Connecting to server")
	supportedDevices = getSupportedDevices(AWSGataway, sharedSecret)
	printToLog("OK")
	localDeviceDescriptors = getDevices()
	index = chooseInstaller(supportedDevices, localDeviceDescriptors)
	
	if not os.path.isfile(os.path.join(os.environ["QC"], brianDirname, "config.json")):
		printToLog("Sending registration data")
		response = sendRegistration(AWSGataway, sharedSecret, getMACs(), parseLicense(), [supportedDevices[index]], localDeviceDescriptors)
		printToLog(response, verbose=False)
	
	printToLog("done")
	
	downloadAndInstall(supportedDevices[index])

def updateScript():
	scriptPath = os.path.abspath(args.script_path)
	
	printToLog("Looking for newer version of the installer")
	response = getScriptUpdateLink(AWSGataway, sharedSecret, "%i_%i_%s_%s"%(versionMajor, versionMinor, buildFlag, "brianqc_installer.sh"))
	printToLog(json.dumps(response, indent=2), verbose=False)
	printToLog("done")
	
	mustUpdate = False
	
	text = httpsGetBigRawData(response["url"]).read().decode()
	
	for m in re.findall("installerTimeStamp[ ]*=[ ]*([0-9]+)", text):
		if int(m) > installerTimeStamp:
			mustUpdate = True
	
	if mustUpdate:
		with open(scriptPath, "w") as f:
			f.write(text)
		print("Updated installer script, restarting")
		os.environ["WITH_GPU"] = "1"
		os.environ["BRIANQC_UPDATED_RESTART"] = "1"
		subprocess.check_call([scriptPath, "--no-update"])
		sys.exit(0)
	else:
		print("Installer is already up-to-date")

def installerFromPackage():
	#TODO: rewrite it with the new version!
	pass
	
	#supportedDevices = []
	
	#for installer in packedInstallers:
		#supportedDevices.append(installer['deviceName'])
	
	#if len(packedInstallers) > 0:
		#index = chooseInstaller(supportedDevices)
		#unpackAndInstall(index)
	#else:
		#print("ERROR: Failed to install BrianQC, because network is not available and the instaler does not contain the binary packages")
		#print("You can request offline installers on http://brianqc.com/")
		#sys.exit(1)

def configQchemEnvFile(fileName, markerText, value):
	if os.path.exists(fileName):
		with open(fileName, "r") as f:
			oldConfig = f.read()
		
		markerIndex = oldConfig.rfind(markerText)
		placeNewMarker = True
		markerFull = markerText + value
		
		if markerIndex >= 0:
			endIndex = oldConfig.find("\n", markerIndex)
			if endIndex >= 0:
				readBack = oldConfig[markerIndex + len(markerText):endIndex]
			
			if oldConfig[markerIndex-1] != '\n' or readBack != value:
				printToLog("WARNING: %s already contains the BRIANQC_INSTALL_PATH but it is not consistent"%(fileName))
			else:
				placeNewMarker = False
		
		if placeNewMarker:
			with open(fileName, "a+") as f:
				f.write("\n%s\n"%(markerFull))
			printToLog('Appended "%s" to %s'%(markerFull, fileName))
		else:
			printToLog('%s already contains "%s"'%(fileName, markerFull))
	else:
		printToLog("ERROR: Cannot find %s, you will need to configure it manually"%(fileName))

def configQchemEnv():
	if not "QC" in os.environ:
		printToLog("ERROR: Cannot find QC environment variable! Cannot configure qcenv script!")
		sys.exit(1)
	
	QC = os.environ['QC']
	
	BRIANQC_INSTALL_PATH = os.path.abspath(os.path.join(os.environ["QC"], brianDirname))
	configQchemEnvFile(os.path.join(QC, "qcenv.sh"), "export BRIANQC_INSTALL_PATH=", BRIANQC_INSTALL_PATH)
	configQchemEnvFile(os.path.join(QC, "qcenv.csh"), "setenv BRIANQC_INSTALL_PATH ", BRIANQC_INSTALL_PATH)

if not "QC" in os.environ:
	printToLog("ERROR: Cannot find QC environment variable! Cannot configure qcenv script!")
	sys.exit(1)

if (sys.version_info[0], sys.version_info[1], sys.version_info[2]) < (2, 7, 9):
	if len(packedInstallers) > 0:
		printToLog("WARNING: Installer needs at least Python 2.7.9 for Internet based install")
		internetInstallEnabled = False
	else:
		printToLog("ERROR: Installer needs at least Python 2.7.9 for Internet based install")
		sys.exit(1)

installSuccess = False

if not args.no_internet:
	try:
		if not args.no_update:
			updateScript()
		
		checkGLibcVersion()
		installFromInternet()
		installSuccess = True
	except Exception as e:
		printToLog(type(e), verbose=False)
		printToLog(e)
		printToLog("WARNING: Installing from the Internet failed!")

if not installSuccess:
	checkGLibcVersion()

	if len(packedInstallers) == 0:
		printToLog("If you wish to use the offline installer, please contact us at support@brianqc.com")
		sys.exit(1)
	
	installerFromPackage()

configQchemEnv()

print("")
print("BrianQC GPU module")
print("http://brianqc.com")
print("support@brianqc.com")

sys.exit(0)



EOM

exec ${PYTHON_INTERPRETER} -c "$CODE" "${BASH_SOURCE[0]}" $*

