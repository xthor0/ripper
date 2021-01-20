#!/bin/bash

### NOTE:
# in order for makemkv (or, makemkvcon, even) to be able to properly detect the title track on scrambled BDROMs,
# an old version of Java MUST be installed. https://www.oracle.com/java/technologies/javase-downloads.html - get Java SE 8

function _exit_err(){
    # TODO: see if API keys for Pushover are set, and if so, push one over.
    exit 255
}

# ensure output directories exist
discinfo_output_dir="${HOME}/discinfo"
output_dir=/storage/videos/rips
for directory in "${discinfo_output_dir}" "${output_dir}"; do
    if [ ! -d "${directory}" ]; then
        echo "${directory} does not exist -- creating."
        mkdir "${directory}"
    fi
done

# create temp file
echo "Scanning disc for title, please wait..."
discinfo=$(mktemp -p "${discinfo_output_dir}" discinfo.tempfile.XXXXX)
makemkvcon --progress=-stdout -r info dev:/dev/sr0 > $discinfo

# get disc title
title=$(cat $discinfo | grep '^DRV:0' | cut -d \, -f 6 | tr -d \")

# if title is not set, exit
if [ -z "$title" ]; then
	echo "Title could not be determined from disc - exiting."
	_exit_err
fi

# save the discinfo file and then delete it (for debugging purposes)
discinfo_backup="${HOME}/discinfo/${title}.txt"
if [ ! -f "${discinfo_backup}" ]; then
	discinfo_backup="${HOME}/discinfo/${title}.txt"
    mv ${discinfo} "${discinfo_backup}"
    discinfo="${discinfo_backup}"
fi

# let's see if Java was able to determine what the title track of this disc is.
grep -q FPL_MainFeature ${discinfo}
if [ $? -eq 0 ]; then
    # if this check passes, it means that Java was able to properly determine the correct feature track
    titletrack=$(grep '^TINFO:.*27.*FPL_MainFeature' ${discinfo} | cut -d : -f 2 | cut -d , -f 1)
    echo "Java located the title track: ${titletrack}"
else
    # some discs (I'm looking at you, John Wick) have a gazillion tracks in the output. 337, on the Amazon version of the disc
    # I bought. on discs like this, the only way forward is either the Windows PowerDVD hack here - https://www.makemkv.com/forum/viewtopic.php?t=16251
    # or, checking the forums for the correct playlist.
    # so, this is a quick n' dirty hack to make sure we're not ripping a disc that might fill up my hard drive.
    echo "Java was unable to locate the title track of this disc."
    trackcount=$(grep -c ^TINFO:.*,27,0, ${discinfo})
    if [ ${trackcount} -gt 100 ]; then
        echo "Sorry, this disc has more than 100 tracks, playlist obfuscation may be going on."
        echo "You should rip this disc manually and make sure it is what it purports to be."
        _exit_err
    else
        # this should find the longest track
        titletrack=$(grep '^TINFO:.*,9,0,' ${discinfo} | cut -b 7- | tr , ' ' | tr -d \" | awk '{ print $4 " " $1 }' | sort -rn | head -n1 | awk '{ print $2 }')
        echo "Found longest track: ${titletrack}"
    fi
fi

# make sure before we proceed that titletrack is a DIGIT
re='^[0-9]+$'
if ! [[ ${titletrack} =~ ${re} ]] ; then
   echo "Whoops - something went wrong. ${titletrack} is either empty or not a number."
   _exit_err
fi

echo "Ripping title track ${titletrack} from ${title} with makemkvcon..."
log=$(mktemp -t makemkvcon.log.XXXX)
makemkvcon --progress=-stdout -r --decrypt --directio=true mkv dev:/dev/sr0 ${titletrack} /storage/videos/rips >& ${log}
if [ $? -eq 0 ]; then
    echo "Rip completed."
    rm -f ${log}
else
    echo "Oops - something went wrong. Take a look at ${log} for more information. Exiting now..."
    _exit_err
fi

# TODO: I'd love to automate Filebot, but the names that come off these discs... are they gonna be suitable for a filebot
# lookup?
# filebot.sh -rename Aladdin\ Diamond\ Edition_t00.mkv --db themoviedb --q "Aladdin (1992)"


# TODO: HandBrakeCLI here
# don't forget to change things like quality, I should use mediainfo to determine DVD, BDROM, or 4k

# the end
exit 0
