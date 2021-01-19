#!/bin/bash

# ensure discinfo directory exists
output_dir="${HOME}/discinfo"
if [ ! -d "${output_dir}" ]; then
    mkdir "${output_dir}"
fi

# create temp file
echo "Scanning disc for title, please wait..."
discinfo=$(mktemp -p "${output_dir}" discinfo.tempfile.XXXXX)
makemkvcon --progress=-stdout -r info dev:/dev/sr0 > $discinfo

# get disc title
title=$(cat $discinfo | grep '^DRV:0' | cut -d \, -f 6 | tr -d \")

# if title is not set, exit
if [ -z "$title" ]; then
	echo "Title could not be determined from disc - exiting."
	exit 255
fi

# save the discinfo file and then delete it (for debugging purposes)
discinfo_backup="${HOME}/discinfo/${title}.txt"
if [ ! -f "${discinfo_backup}" ]; then
	discinfo_backup="${HOME}/discinfo/${title}.txt"
    mv ${discinfo} "${discinfo_backup}"
    discinfo="${discinfo_backup}"
fi

# look at the discinfo and figure out what the longest title is
# this really only works for movies. it'll remove any bonus content or whatnot.
grep TINFO:.*,9,0, "${discinfo}" | cut -d \, -f 4 | tr -d \" | sort -rn | grep -v ^0 | while read length; do
    # get the title for this length
    track=$(grep ${length} "${discinfo}" | cut -d \: -f 2 | cut -d \, -f 1)
    echo "Extracting track ${track} from ${title}..."
    makemkvcon --progress=-stdout --minlength=600 -r --decrypt --directio=true mkv dev:/dev/sr0 ${track} /storage/videos/rips
    echo "Completed."
done

# that's the end right now