#!/bin/bash
# Script to configure secondary database VM


echo 'Creating file systems ...' 
/usr/sbin/parted /dev/sdc mklabel gpt
/usr/sbin/parted -a opt /dev/sdc mkpart primary xfs 0% 100%
mkdir /u02 
/usr/sbin/mkfs.xfs /dev/sdc1
mount /dev/sdc1 /u02
mkdir /u02/oradata /u02/orarecv 
chown oracle:oinstall /u02 -R
diskuuid=`ls  -l /dev/disk/by-uuid | grep sdc1 |  awk '{i=NF-2;print $i}'`
mntopts=`sudo mount | grep u02 | awk '{print $NF}' | sed 's/(//' | sed 's/)//'`
echo UUID=$diskuuid /u02 xfs $mntopts 0 0 >> /etc/fstab
echo 'Finished creating file systems' 
echo 'disable firewall'
systemctl stop firewalld
systemctl disable firewalld


sudo -E su - oracle <<"SUEOF"
#!/bin/bash

export _primaryOraSid="oradb01"
export _stdbyOraSid="oradb02"
export _oraHome="/u01/app/oracle/product/19.0.0/dbhome_1"
export _oraInvDir="/u01/app/oraInventory"
export _oraOsAcct="oracle"
export _oraOsGroup="oinstall"
export _oraCharSet="WE8ISO8859P15"
export _oraMntDir="/u02"
export _oraDataDir="${_oraMntDir}/oradata"
export _oraFRADir="${_oraMntDir}/orarecv"
export _oraSysPwd=oracleA1
export _oraRedoSizeMB=500
export _oraLsnr="LISTENER"
export _oraLsnrPort=1521
export _vmName1="primary"
export _vmName2="secondary"
export _vmName3="observer"
export _vmNbr1="vm01"
export _vmNbr2="vm02"
export _vmNbr3="vm03"
export _vmDomain="internal.cloudapp.net"
export ORACLE_SID=${_primaryOraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:${PATH}
export TNS_ADMIN=${_oraHome}/network/admin 


echo Modify tnsnames.ora 
cat >> ${TNS_ADMIN}/tnsnames.ora << TNSHERE

${_primaryOraSid}=
  (DESCRIPTION = (FAILOVER = ON)(LOAD_BALANCE = OFF)
    (ADDRESS_LIST =
      (ADDRESS = (PROTOCOL = TCP)(HOST = ${_vmName1}.${_vmDomain})(PORT = 1521))
      (ADDRESS = (PROTOCOL = TCP)(HOST = ${_vmName2}.${_vmDomain})(PORT = 1521))
    )
    (CONNECT_DATA = 
        (SERVICE_NAME = PRIMARY)
        (SERVER = DEDICATED)
    )
  ) 

${_primaryOraSid}_${_vmNbr1}=
  (DESCRIPTION =
    (ADDRESS_LIST =
      (ADDRESS = (PROTOCOL = TCP)(HOST = ${_vmName1}.${_vmDomain})(PORT = 1521))
    )
    (CONNECT_DATA =  
        (SERVICE_NAME = ${_primaryOraSid}_${_vmNbr1})
        (SERVER = DEDICATED)
    )
  )

${_stdbyOraSid}_${_vmNbr2}=
  (DESCRIPTION =
    (ADDRESS_LIST =
      (ADDRESS = (PROTOCOL = TCP)(HOST = ${_vmName2}.${_vmDomain})(PORT = 1521))
    )
    (CONNECT_DATA =
      (SERVICE_NAME = ${_stdbyOraSid}_${_vmNbr2})
      (SERVER = DEDICATED)
    )
  )

${_primaryOraSid}_dgmgrl =
  (DESCRIPTION =
    (ADDRESS_LIST = 
    	(ADDRESS = (PROTOCOL = TCP)(HOST = ${_vmName1}.${_vmDomain})(PORT = 1521))
    )
    (CONNECT_DATA =
            (SERVER = DEDICATED)
            (SERVICE_NAME = ${_primaryOraSid}_dgmgrl)
	  )
  )

${_stdbyOraSid}_dgmgrl =
  (DESCRIPTION =
    (ADDRESS_LIST = 
    	(ADDRESS = (PROTOCOL = TCP)(HOST = ${_vmName2}.${_vmDomain})(PORT = 1521))
    )
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${_stdbyOraSid}_dgmgrl)
	  )
  )

${_primaryOraSid}_taf =
  (DESCRIPTION = 
    (FAILOVER = ON)
    (LOAD_BALANCE = OFF)
    (ADDRESS_LIST =
      (ADDRESS = (PROTOCOL = TCP)(HOST = ${_vmName1}.${_vmDomain})(PORT = 1521))
      (ADDRESS = (PROTOCOL = TCP)(HOST = ${_vmName2}.${_vmDomain})(PORT = 1521))
    )
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = PRIMARY)
    )
    (FAILOVER_MODE =
      (TYPE = SELECT)
      (METHOD = BASIC)
      (RETRIES = 300)
      (DELAY = 1)
    )
  )

TNSHERE

echo create standby database
dbca -silent -createDuplicateDB \
    -gdbName ${_primaryOraSid} \
    -sysPassword ${_oraSysPwd} \
    -sid ${_stdbyOraSid} \
    -createAsStandby \
    -dbUniqueName ${_stdbyOraSid} \
    -primaryDBConnectionString ${_vmName1}.${_vmDomain}:${_oraLsnrPort}/${_primaryOraSid}

echo create the Listener.ora config in Secondary
cat >> ${_oraHome}/network/admin/listener.ora << EOF
SID_LIST_${_oraLsnr}=
(SID_LIST =
  (SID_DESC = 
    (GLOBAL_DBNAME = ${_stdbyOraSid}_dgmgrl)
    (ORACLE_HOME = ${_oraHome})
    (SID_NAME = ${_stdbyOraSid})
  )
)
EOF
lsnrctl reload ${_oraLsnr}

export ORACLE_SID=${_stdbyOraSid}
sqlplus -S / as sysdba << __EOF__

ALTER SYSTEM SET SERVICE_NAMES='${_stdbyOraSid}','${_stdbyOraSid}_dgmgrl' SCOPE=BOTH;
ALTER SYSTEM SET LOG_ARCHIVE_CONFIG='DG_CONFIG=${_primaryOraSid}' SCOPE=BOTH;
ALTER DATABASE SET STANDBY DATABASE TO MAXIMIZE AVAILABILITY;
ALTER DATABASE FLASHBACK ON;

__EOF__

echo copy orapw file from vm1 to vm2  
cd /tmp
wget "https://aka.ms/downloadazcopy-v10-linux"
tar -xvf ./downloadazcopy-v10-linux
export AZCOPY_AUTO_LOGIN_TYPE=MSI
/tmp/azcopy_linux_amd64_10.20.1/azcopy cp https://sharedstore1109.blob.core.windows.net/orashare/orapw${_primaryOraSid} "${_oraHome}/dbs/orapw${_primaryOraSid}"
echo completed file copy

SUEOF