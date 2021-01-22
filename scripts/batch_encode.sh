#!/bin/bash

startDate=$(date)

# output dir for encoded files
encode_dir=/storage/videos/encoded

log=$(mktemp -t makemkvcon.log.XXXX)
find . -maxdepth 1 -type f -iname "*.mkv" | while read inputfile; do
	newfile=$(basename "$inputfile" .mkv)
    output_file="${encode_dir}/${newfile}.mkv"
	if [ -f "${output_file}" ]; then
		echo "Target already exists: ${output_file} -- skipping."
		continue
	fi
	
	echo "Encoding ${inputfile} to ${output_file}..."
	start=$(date +%s)
	echo | HandBrakeCLI -m -E ac3 -B 384 -6 5point1 -e x264 --encoder-preset veryfast -q 21 -i "${inputfile}" -o "${output_file}" 2> ${log}
    if [ $? -eq 0 ]; then
        rm -f ${log}
    else
        echo "Error - check ${log} for details."
    fi
	end=$(date +%s)
	diff=$(($start-$end))
	echo "$(($diff / 60)) minutes and $(($diff % 60)) seconds elapsed."
done

endDate=$(date)

# pushover message
test -f ${HOME}/.pushover-api-keys
if [ $? -eq 0 ]; then
    . ${HOME}/.pushover-api-keys
    curl -s --form-string "token=${apitoken}" --form-string "user=${usertoken}" --form-string "message=Notification: Batch HandBrake job completed. :: Start: ${startDate} -- End: ${endDate}" https://api.pushover.net/1/messages.json
fi

echo "All done!"

exit 0
