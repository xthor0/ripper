#!/bin/bash

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

echo "Begin at: $(date)"
begin=$(date +%s)

[ ! -d output ] && mkdir output
[ ! -d output/log ] && mkdir output/log

# name the output CSV and write a header row
datestamp="$(date +%Y%m%d.%s)"
csv="results-${HOSTNAME}-${datestamp}.csv"
echo "source,encoder,fps,source_size,target_size,seconds,decrease" > "${csv}"

# define array of encoders
# software only = x264, x265
# intel = qsv_h264, qsv_h265
# nvidia = nvenc_h264, nvenc_h265
encoders=("qsv_h264" "qsv_h265")

for inputfile in sources/*.mkv; do
    for encoder in ${encoders[@]}; do

        # figure out what encoder preset we should use
        unset encoderPreset
        case ${encoder} in
            x26*) encoderPreset="veryfast";;
            qsv_*) encoderPreset="speed";;
            nvenc*) encoderPreset="fast";;
        esac

        # if encoderPreset is still null, something didn't work
        if [ -z "${encoderPreset}" ]; then
            echo "Could not determine encoder preset -- exiting."
            exit 255
        fi

        [ ! -d output/${encoder} ] && mkdir output/${encoder}
        newfile=$(basename "$inputfile" .mkv)
        target="output/${encoder}/${newfile}-${encoder}.mkv"
        log="output/log/${newfile}-${encoder}.log"
        
        echo "Processing ${inputfile} to $(pwd)/${target}..."
        start=$(date +%s)
        echo | flatpak run --command=HandBrakeCLI fr.handbrake.ghb -E ac3 -B 384 -6 5point1 -e ${encoder} --encoder-preset ${encoderPreset} -q 21 -i "${inputfile}" -o "${target}" 2> "${log}"
        stop=$(date +%s)

        # collect elapsed time in seconds
        seconds=$(expr ${stop} - ${start})
        
        # figure out average FPS
        fps=$(grep 'average encoding speed' "${log}" | awk '{ print $9 }')

        # we need the source file size
        source_size=$(du -m "${inputfile}" | awk '{ print $1 }')

        # and also the target file size
        target_size=$(du -m "${target}" | awk '{ print $1 }')

        # figure out % difference between files?
        decrease=$(echo "scale=4;(($source_size-$target_size)/$source_size)*100" | bc | cut -c -5)

        # output it to the screen (more later)
        echo "Source: ${inputfile} -- Encoder: ${encoder} -- Time: ${seconds} -- FPS: ${fps} -- source size: ${source_size} -- target size: ${target_size}"

        # put it in a CSV, why not
        echo "${inputfile},${encoder},${fps},${source_size},${target_size},${seconds},${decrease}" >> "${csv}"
    done
done

echo "End at: $(date)"
end=$(date +%s)
total_elapsed=$(expr ${end} - ${begin})
echo "Total elapsed seconds: ${total_elapsed}"

pushover_msg HandBrake benchmark completed on ${HOSTNAME} -- total elapsed seconds: ${total_elapsed}

exit 0
