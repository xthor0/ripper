#!/bin/bash

### NOTE:
# in order for makemkv (or, makemkvcon, even) to be able to properly detect the title track on scrambled BDROMs,
# an old version of Java MUST be installed. https://www.oracle.com/java/technologies/javase-downloads.html - get Java SE 8

# tools I installed for this script to work:
# apt install handbrake-cli makemkv-oss makemkv-bin mediainfo mkvtoolnix jq bc

function _exit_err(){
    # TODO: see if API keys for Pushover are set, and if so, push one over.
    # spit out the cdrom. may as well.
    eject sr0
    exit 255
}

# set handbrake profile info
handbrake_preset_file="$(pwd)/../handbrake-presets/MKV-HQ.json"
handbrake_preset=$(cat "${handbrake_preset_file}" | jq -r '.PresetList[0].PresetName')

# ensure output directories exist
discinfo_output_dir="${HOME}/discinfo"
output_dir=/storage/videos/rips
encode_dir=/storage/videos/encoded
for directory in "${discinfo_output_dir}" "${output_dir}" "${encode_dir}"; do
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

# set the title of the disc to match what we got from the XML file
echo "Adding movie title to mkv metadata..."
mkvpropedit "${output_dir}/${outputfile}" --edit info --set "title=${title}"

# encode the file with HandBrakeCLI
# TODO: use mediainfo to determine resolution, and change profile accordingly. Maybe.
echo "Encoding with HandBrake..."
log=$(mktemp -t handbrake.log.XXXX)
HandBrakeCLI --preset-import-file "${handbrake_preset_file}" -Z "${handbrake_preset}" -i "${output_dir}/${outputfile}" -o "${encode_dir}/${outputfile}" 2> ${log}
if [ $? -eq 0 ]; then
    echo "HandBrake encode successful."
    rm -f ${log}
else
    echo "Error: HandBrake exited unsuccessfully. Check ${log} for more details."
    _exit_err
fi

# rename the file using Filebot (makes life easier for Plex)
echo "Renaming file with FileBot..."
filebot.sh -rename "${encode_dir}/${outputfile}" --db themoviedb --q "${title}"

# the end
echo "Movie ${title} has been successfully encoded."
# TODO: pushover message
exit 0
