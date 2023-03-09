#!/bin/bash

###
# BACKUP-GTM - archiving GTM Regions
# by Cless
#
# Requirements:
# * in case of manual regions list to backup - change list of GTM Regions in the file regionsList.txt
# * change var's paths in "paths" section
# * change type of regionListFileType (1 - Manual, 2- Auto)
###


# ---
# VARS
# ---

# date
yearCurrent=`date +%Y`
monthCurrent=`date +%m`
dayOfMonthCurrent=`date +%d`
dateTimeCurrent=`date +%Y-%m-%d_%H-%M-%S`

# test
# monthCurrent=03
# dayOfMonthCurrent=08

# paths
rootDir="/root/backup-gtm"
gtmDbDir="/home/BASE/MNA"
backupBufferPath="/home/BKUP/TMP"
gtmProfileFile="/chroot/gtm/gtmprofile"
zpaq=${rootDir}/zpaq/zpaq
zpaqBackupDir=/home/BKUP/weekly/${yearCurrent}/${monthCurrent}
gzBackupDir=/home/BKUP/daily
#zpaqBackupDir=${rootDir}/backup/weekly/${yearCurrent}/${monthCurrent}
#gzBackupDir=${rootDir}/backup/daily
gzBackupLeaveLastNFiles="7" # leave last N newest archives in GZ arch dir
zpaqExtractedForCheckDir=${rootDir}/extracted_for_check/zpaq
gzExtractedForCheckDir=${rootDir}/extracted_for_check/gz
backupLogDir=${rootDir}/log
backupLogFile=${backupLogDir}/backupLog.txt
backupStatusFile=${backupLogDir}/backupStatus.txt
checkMarkerFileName="checkMarker.txt"

# select region list file type:
# 1 - Manual (you have to manually fill in the list of REGIONS to backup)
# 2 - Auto (list filled with REGIONS automatically from GTM)
regionListFileType=1

# regionListFileType set
if [ ${regionListFileType} == 1 ]; then regionsListFile=${rootDir}/regionsListManual.txt; fi
if [ ${regionListFileType} == 2 ]; then regionsListFile=${rootDir}/regionsListAuto.txt; fi

# utils
tar=`which tar`
pigz=`which pigz`


# ---
# COMMON ACTIONS
# ---

# get gtm vars
source ${gtmProfileFile}

# create log dir
if ! [ -d "${backupLogDir}" ]; then
        mkdir -p "${backupLogDir}"
fi

# delete backup log file
if test -f "${backupLogFile}"; then
    rm -f "${backupLogFile}"
fi

# delete backup status file
if test -f "${backupStatusFile}"; then
    rm -f "${backupStatusFile}"
fi

# auto get regions list from GTM
# (IF regionListFileType = 2 (Auto))
if [ regionListFileType == 2 ]; then
	# get list of REGIONS from GTM and put them to list file
	$gde 'sh -r' | sed '1,/\-----/d' | awk '{print $1}' > ${regionsListFile}
fi

# create array of region names with paths from region list file
arrayRegionsList=()
while IFS= read -r line || [[ "$line" ]];
  do
    arrayRegionsList+=( "$line" )
  done < <( cat "${regionsListFile}" | grep -v "^#" )

# debug
echo "Number of elements (regions) in array: ${#arrayRegionsList[*]}"


# ---
# FOR EVERY REGION NAME FROM LIST TXT DO:
# ---

for regionName in "${arrayRegionsList[@]}";
do
    # debug
    echo "regionName: ${regionName}"

	# check if region exists in gtm
	if [[ -n `$gde 'sh -r' | grep "${regionName}"` ]]; then
		echo "-REGION-EXIST_OK-";
		regionExist="1";
        regionExistStatus="-REGION-EXIST_OK-";
	else		
		echo "-REGION-EXIST_FAIL-";
		regionExist="0";		
		regionExistStatus="-REGION-EXIST_FAIL-";
	fi

	# check if segment file exist
	if test -f "${gtmDbDir}/${regionName}.dat"; then
		echo "-SEGMENT-FILE-EXIST_OK-";
		segmentFileExist="1";
		segmentFileExistStatus="-SEGMENT-FILE-EXIST_OK-";
	else
		echo "-SEGMENT-FILE-EXIST_FAIL-";
		segmentFileExist="0";
		segmentFileExistStatus="-SEGMENT-FILE-EXIST_FAIL-";
	fi

    # if region EXISTS _and_ segment file EXISTS
    if [[ ${regionExist} == 1 && ${segmentFileExist} == 1 ]]; then

		# rm dir for segment file
		if [ -d "${backupBufferPath}/${regionName}" ]; then
				rm -rf "${backupBufferPath}/${regionName}";
		fi

		# create dir for segment file
		if ! [ -d "${backupBufferPath}/${regionName}" ]; then
			mkdir -p "${backupBufferPath}/${regionName}"
		fi

		# create temp segment backup file in buffer dir
		mupip backup -online ${regionName} ${backupBufferPath}/${regionName}/

		# if dayOfMonthCurrent = 1,8,15,22
		# create weekly backup
		if [[ ${dayOfMonthCurrent} == "01" || ${dayOfMonthCurrent} == "08" || ${dayOfMonthCurrent} == "15" || ${dayOfMonthCurrent} == "22" ]]; then

			# ---
			# ZPAQ - ARCH
			# ---

			# delete chk marker
			if test -f "${backupBufferPath}/${regionName}/${checkMarkerFileName}"; then
				rm -r "${backupBufferPath}/${regionName}/${checkMarkerFileName}"
			fi

			# create chk marker in region dir
			echo ${dateTimeCurrent} > "${backupBufferPath}/${regionName}/${checkMarkerFileName}"

			# create root dir for segment backup in common backup dir
			if ! [ -d "${zpaqBackupDir}/${regionName}" ]; then
				mkdir -p "${zpaqBackupDir}/${regionName}"
			fi

			# arch segment
			cd "${backupBufferPath}"
			${zpaq} a "${zpaqBackupDir}/${regionName}/${regionName}_???.zpaq" "${regionName}"

			# get regionArchStatus
			if [[ $? == "0" ]]; then
				echo "-ZPAQ_ARCH_OK-";
				regionZpaqArchStatus="-ZPAQ_ARCH_OK-"
			else
				echo "-ZPAQ_ARCH_FAIL-";
				regionZpaqArchStatus="-ZPAQ_ARCH_FAIL-"
			fi


			# ---
			# ZPAQ - EXTRACT SEGMENT FOR CHECK
			# ---

			# create segmentExtractedForCheckDir
			if ! [ -d "${zpaqExtractedForCheckDir}" ]; then
				${mkdir} -p "${zpaqExtractedForCheckDir}"
			fi

			# delete every extracted for check segment
			if [ -d "${zpaqExtractedForCheckDir}/${regionName}" ]; then
				rm -rf "${zpaqExtractedForCheckDir}/${regionName}"
			fi

			# extract only checkMarker file from segment arch
			cd "${zpaqBackupDir}/${regionName}"
			${zpaq} x "${regionName}_???.zpaq" -force -to "${zpaqExtractedForCheckDir}" -only "${regionName}/${checkMarkerFileName}"

			# get dbExtrStatus
			if [[ $? == "0" ]]; then
				echo "-ZPAQ_EXTRACT_OK-";
				regionZpaqExtrStatus="-ZPAQ_EXTRACT_OK-"
			else
				echo "-ZPAQ_EXTRACT_FAIL-";
				regionZpaqExtrStatus="-ZPAQ_EXTRACT_FAIL-"
			fi

			# find currentdate in db marker file
			cat "${zpaqExtractedForCheckDir}/${regionName}/${checkMarkerFileName}" | grep "${dateTimeCurrent}"

			# checkmarker status
				if [[ $? == "0" ]]; then
				echo "-ZPAQ_CHECKMARKER_OK-";
				regionZpaqCheckMarkerStatus="-ZPAQ_CHECKMARKER_OK-"
			else
				echo "-ZPAQ_CHECKMARKER_FAIL-";
				regionZpaqCheckMarkerStatus="-ZPAQ_CHECKMARKER_FAIL-"
			fi
		fi


		# ---
		# GZ - ARCH
		# ---

		# delete chk marker
		if test -f "${backupBufferPath}/${regionName}/${checkMarkerFileName}"; then
			rm -r "${backupBufferPath}/${regionName}/${checkMarkerFileName}"
		fi

		# create chk marker in region dir
		echo ${dateTimeCurrent} > "${backupBufferPath}/${regionName}/${checkMarkerFileName}"

		# create root dir for segment backup in common backup dir
		if ! [ -d "${gzBackupDir}/${regionName}" ]; then
			mkdir -p "${gzBackupDir}/${regionName}"
		fi

		# arch segment
		cd "${backupBufferPath}"
		${tar} cf - "${regionName}" | ${pigz} -k > "${gzBackupDir}/${regionName}/${regionName}_${dateTimeCurrent}.tar.gz"

		# get dbArchStatus
		if [[ $? == "0" ]]; then
			echo "-GZ_ARCH_OK-";
			regionGzArchStatus="-GZ_ARCH_OK-"
		else
			echo "-GZ_ARCH_FAIL-";
			regionGzArchStatus="-GZ_ARCH_FAIL-"
		fi

		# leave last N newest archives in GZ arch dir
		if [[ -d ${gzBackupDir}/${regionName} ]]; then
				cd ${gzBackupDir}/${regionName}
				ls -lt | sed /^total/d \
				| awk -v gzBackupLeaveLastNFiles=${gzBackupLeaveLastNFiles} 'FNR>gzBackupLeaveLastNFiles {print $9}' \
				| xargs rm -f {};
		fi


        # ---
        # GZ - EXTRACT SEGMENT FOR CHECK
        # ---

        # create ExtractedForCheckDir
        if ! [ -d "${gzExtractedForCheckDir}" ]; then
            mkdir -p "${gzExtractedForCheckDir}"
        fi

        # delete every extracted for check db
        if [ -d "${gzExtractedForCheckDir}/${regionName}" ]; then
            rm -rf "${gzExtractedForCheckDir}/${regionName}"
        fi

        # extract only checkMarker file from segment arch
        cd "${gzBackupDir}/${regionName}"
        ${tar} -xvzf "${regionName}_${dateTimeCurrent}.tar.gz" -C "${gzExtractedForCheckDir}" "${regionName}/${checkMarkerFileName}"

        # get dbExtrStatus
        if [[ $? == "0" ]]; then
            echo "-GZ_EXTRACT_OK-";
            regionGzExtrStatus="-GZ_EXTRACT_OK-"
        else
            echo "-GZ_EXTRACT_FAIL-";
            regionGzExtrStatus="-GZ_EXTRACT_FAIL-"
        fi

        # find currentdate in db marker file
        cat "${gzExtractedForCheckDir}/${regionName}/${checkMarkerFileName}" | grep "${dateTimeCurrent}"

        # if
            if [[ $? == "0" ]]; then
            echo "-GZ_CHECKMARKER_OK-";
            regionGzCheckMarkerStatus="-GZ_CHECKMARKER_OK-"
        else
            echo "-GZ_CHECKMARKER_FAIL-";
            regionGzCheckMarkerStatus="-GZ_CHECKMARKER_FAIL-"
        fi


        # write backup log
        echo "${regionName} : ${regionZpaqArchStatus} ${regionZpaqExtrStatus} ${regionZpaqCheckMarkerStatus} ${regionGzArchStatus} ${regionGzExtrStatus} ${regionGzCheckMarkerStatus}" >> "${backupLogFile}"

    else
        
		# write backup log
        echo "${regionName} : ${regionExistStatus} ${segmentFileExistStatus}" >> "${backupLogFile}"
    fi
	
	# delete segment backup in buffer dir
	if [ -d "${backupBufferPath}/${regionName}" ]; then
		rm -rf "${backupBufferPath}/${regionName}"
	fi

done

# IF there's BACKUP_FAIL in log file - write FAIL into status file
if [[ -n `cat "${backupLogFile}" | grep "_FAIL-"` ]]; then
    echo "-BACKUP_FAIL-";

    # write OK backup status
    echo "FAIL" > ${backupStatusFile}
else
    # IF there's BACKUP_OK in log file - write OK into status file
    if [[ -n `cat "${backupLogFile}" | grep "_OK-"` ]]; then
        echo "-BACKUP_OK-"

        # write FAIL backup status
        echo "OK" > ${backupStatusFile}
    else
        echo "-BACKUP_FAIL-"

        # backup log
        echo "FAIL" > ${backupStatusFile}
    fi
fi
