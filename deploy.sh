#!/bin/bash

jekyll build && \
$(dirname $0)/generate-meta.sh && \
rsync --progress -av _site/ sanjoyd_playingwithpointers@ssh.phx.nearlyfreespeech.net:/home/public/
