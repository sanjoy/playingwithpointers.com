#!/bin/bash

jekyll build
rsync --progress -av _site/ sanjoyd_playingwithpointers@ssh.phx.nearlyfreespeech.net:/home/public/
