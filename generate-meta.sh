#!/bin/bash

SITE_NAME='http://www.playingwithpointers.com/'

find _site -name '*.html' | xargs basename | gsed "s|^|${SITE_NAME}|" > sitemap.txt
