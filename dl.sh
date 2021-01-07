#!/bin/bash

<<'###'
Javascript to paste in console, for fast copy paste of the whole page links, in the correct format.
Copy paste the below and place inside the `courses_list` map:

(function() {
	out = [];
	document.querySelectorAll('a.course-btn').forEach(function(item, idx) {
		out.push('"'+ item.href +'"');
	});
	
	console.log(out.join("\n"));
})();

###


declare -a courses_list=(
"https://example.com/url/course"
)

CH_DL_BIN=/mnt/d/dev/ch-video-downloader/video_dl.rb


######## -- dont edit below

PARALLEL=false

# idiomatic parameter and option handling in sh
while test $# -gt 0
do
    case "$1" in
        --parallel) PARALLEL=true
            ;;
        --*) echo "bad option $1"
            ;;
        *) echo "argument $1"
            ;;
    esac
    shift
done


for i in "${courses_list[@]}"
do
    echo "[x] Starting $i || Running in parallel: ${PARALLEL}";
    
    if [[ ${PARALLEL} = "true" ]]
    then
        nohup ruby ${CH_DL_BIN} -url "$i" 2>&1 &
    else
        ruby ${CH_DL_BIN} -url "$i";
    fi
done
