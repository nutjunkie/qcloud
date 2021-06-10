#!/bin/sh

export QCPLATFORM=LINUX_Ix86_64
export QC=/usr/local/qchem/qc50
export QCAUX=/usr/local/qchem/qcaux

export PATH=${QC}/bin:${QC}/exe:$PATH
export QCSCRATCH=/scratch

export QCPROG=${QC}/exe/qcprog.exe
export QCPROG_S=${QC}/exe/qcprog.exe
export QCPROG=`dirname $0`/qcprog.exe
export QCPROG_S=`dirname $0`/qcprog.exe_s
