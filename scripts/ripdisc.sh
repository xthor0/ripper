#!/bin/bash

### NOTE:
# in order for makemkv (or, makemkvcon, even) to be able to properly detect the title track on scrambled BDROMs,
# an old version of Java MUST be installed. https://www.oracle.com/java/technologies/javase-downloads.html - get Java SE 8

# tools I installed for this script to work:
# apt install handbrake-cli makemkv-oss makemkv-bin mediainfo mkvtoolnix jq bc curl

# TODO: https://github.com/automatic-ripping-machine/automatic-ripping-machine/blob/v2_master/setup/51-automedia.rules
# create the udev files in /etc/udev/rules.d/
# end goal: This script kicks off automatically when I drop a disc in the drive. I feel like I'm SUPER close!

function pushover_msg() {
    test -f ${HOME}/.pushover-api-keys
    if [ $? -eq 0 ]; then
        . ${HOME}/.pushover-api-keys
        curl -s \
            --form-string "token=${apitoken}" --form-string "user=${usertoken}" --form-string "message=Notification: $*" https://api.pushover.net/1/messages.json
    else
        echo "No pushover keys found in ~/.pushover-api-keys - can't send a message."
    fi
}

function _exit_err(){
    # TODO: see if API keys for Pushover are set, and if so, push one over.
    pushover_msg "Encode failed, see logs."
    exit 255
}

# ensure output directories exist
discinfo_output_dir="${HOME}/discinfo"
output_dir=/storage/videos/rips
encode_dir=/storage/videos/encoded
completed_dir=/storage/videos/completed
for directory in "${discinfo_output_dir}" "${output_dir}" "${encode_dir}" "${completed_dir}"; do
    if [ ! -d "${directory}" ]; then
        echo "${directory} does not exist -- creating."
        mkdir "${directory}"
    fi
done

# TODO: DVD identification
# supposedly I can make a request against metaservices.windowsmedia.com, pass in the CRC, and get the title back.
# thing is, I'm not sure I care - almost everything I own is BDROM.

# dump the disc info using makemkv to a temp file
echo "Scanning disc with makemkv, please wait..."
discinfo=$(mktemp -p "${discinfo_output_dir}" discinfo.tempfile.XXXXX)
makemkvcon --progress=-stdout -r info dev:/dev/sr0 > $discinfo

# if this is a BDROM, we can scrape an xml file and get a human-readable title. Neat!
echo "Checking for BDROM XML..."
mount /dev/sr0
mountpoint -q /media/cdrom0
if [ $? -eq 0 ]; then
    # BDROM mounted successfully
    test -f /media/cdrom0/BDMV/META/DL/bdmt_eng.xml
    if [ $? -eq 0 ]; then
        title=$(cat /media/cdrom0/BDMV/META/DL/bdmt_eng.xml | grep di:name | cut -d \> -f 2 | cut -d \< -f 1 | cut -d \- -f 1 | xargs)
        echo "Title retrieved from BDROM XML: ${title}"
    else
        echo "bdmt_eng.xml does not exist."
    fi
    umount /dev/sr0
else
    echo "Unable to mount disc, skipping title identification from XML."
fi

# if title is empty, let's get it from makemkv
if [ -z "$title" ]; then
    # use what we can get from makemkv
    echo "Disc title is not set, retrieving from makemkv output..."
    title=$(cat ${discinfo} | grep '^DRV:0' | cut -d \, -f 6 | tr -d \")
fi

# if title is STILL not set, exit
if [ -z "$title" ]; then
	echo "Title could not be determined from disc - exiting."
	_exit_err
fi

# save the disc info we got from makemkv, but named so we can reference it
discinfo_backup="${HOME}/discinfo/${title}.txt"
if [ ! -f "${discinfo_backup}" ]; then
	discinfo_backup="${HOME}/discinfo/${title}.txt"
    mv ${discinfo} "${discinfo_backup}"
    discinfo="${discinfo_backup}"
else
    echo "${discinfo_backup} already exists, keeping temp file ${discinfo}."
fi

# let's see if Java was able to determine what the title track of this disc is.
grep -q FPL_MainFeature "${discinfo}"
if [ $? -eq 0 ]; then
    # if this check passes, it means that Java was able to properly determine the correct feature track
    titletrack=$(grep '^TINFO:.*27.*FPL_MainFeature' "${discinfo}" | cut -d : -f 2 | cut -d , -f 1)
    echo "Java located the title track: ${titletrack}"
else
    # some discs (I'm looking at you, John Wick) have a gazillion tracks in the output. (337, on the Amazon version of John Wick)
    # On discs like this, the only way forward is either the Windows PowerDVD hack here - https://www.makemkv.com/forum/viewtopic.php?t=16251
    # or, checking the forums for the correct playlist.
    # so, this is a quick n' dirty hack to make sure we're not ripping a disc that might fill up my hard drive.
    echo "Java was unable to locate the title track of this disc."
    trackcount=$(grep -c ^TINFO:.*,27,0, "${discinfo}")
    if [ ${trackcount} -gt 100 ]; then
        echo "Sorry, this disc has more than 100 tracks, playlist obfuscation may be going on."
        echo "You should rip this disc manually and make sure it is what it purports to be."
        _exit_err
    else
        # this should find the longest track
        titletrack=$(grep '^TINFO:.*,9,0,' "${discinfo}" | cut -b 7- | tr , ' ' | tr -d \" | awk '{ print $4 " " $1 }' | sort -rn | head -n1 | awk '{ print $2 }')
        echo "Found longest track: ${titletrack}"
    fi
fi

# make sure before we proceed that titletrack is a DIGIT
re='^[0-9]+$'
if ! [[ ${titletrack} =~ ${re} ]] ; then
   echo "Whoops - something went wrong. ${titletrack} is either empty or not a number."
   _exit_err
fi

# get the output filename
outputfile=$(grep ^TINFO:${titletrack},27,0, "${discinfo}" | cut -d \" -f 2)

# make sure we're not going to clobber a file that already exists
test -f "${output_dir}/${outputfile}"
if [ $? -eq 0 ]; then
    echo "${output_dir}/${outputfile} already exists. Won't clobber what you've already ripped."
    _exit_err
fi

# TODO: if the encoded target already exists, we should skip it too, maybe?

# start extraction with makemkv
echo "Ripping title track ${titletrack} to ${outputfile} with makemkvcon..."
log=$(mktemp -t makemkvcon.log.XXXX)
(makemkvcon --progress=-stdout -r --decrypt --directio=true mkv dev:/dev/sr0 ${titletrack} "${output_dir}" >& ${log}) &
bgpid=$!
while [ -d /proc/${bgpid} ]; do
    job="$(grep ^PRGC ${log} | tail -n1 | cut -d , -f 3 | tr -d \")"
    jobprog="$(grep ^PRGV ${log} | tail -n1 | cut -d \: -f 2 | cut -d \, -f 1)"
    totalprog="$(grep ^PRGV ${log} | tail -n1 | cut -d \: -f 2 | cut -d \, -f 1)"
    progperc=$(echo "scale=2;(${jobprog} / ${totalprog}) * 100" | bc | head -c-3)
    tput sc
    echo -n "${job} :: ${progperc} %"
    sleep 5
    tput rc
done

# write a newline, or we'll clobber the last status message
echo

wait ${bgpid}
if [ $? -eq 0 ]; then
    echo "makemkvcon completed successfully."
    rm -f ${log}
else
    echo "Oops - something went wrong. Take a look at ${log} for more information. Exiting now..."
    _exit_err
fi

# rename the file using Filebot (makes life easier for Plex)
echo "Renaming file with FileBot..."
filebot -rename "${output_dir}/${outputfile}" --db themoviedb --q "${title}"

# set the output file metadata title to match what we got from filebot. The metadata can be weird.
echo "Determining how filebot named the file..."
newfile="$(ls -Art "${output_dir}" | tail -n1)"
newfilename="$(basename "${newfile}")"
newtitle="$(basename "${newfile}" .mkv)"
echo "New title: ${newtitle}"
echo "Adding movie title to mkv metadata..."
mkvpropedit "${newfile}" --edit info --set "title=${newtitle}"

# encode the file with HandBrakeCLI
# TODO: use mediainfo to determine resolution, and change profile accordingly. Maybe.
echo "Encoding with HandBrake..."
log=$(mktemp -t handbrake.log.XXXX)
HandBrakeCLI -m -E ac3 -B 384 -6 5point1 -e x264 --encoder-preset veryfast -q 21 -i "${newfile}" -o "${encode_dir}/${newfilename}" 2> ${log}
if [ $? -eq 0 ]; then
    echo "HandBrake encode successful."
    rm -f ${log}
else
    echo "Error: HandBrake exited unsuccessfully. Check ${log} for more details."
    _exit_err
fi

# move original source to completed dir. can be deleted later, but allows a re-encode without a re-rip, which is nice.
mv "${newfile}" "${completed_dir}"

# the end
echo "Movie ${title} has been successfully encoded."
pushover_msg "Movie ${title} has been successfully encoded."
exit 0
