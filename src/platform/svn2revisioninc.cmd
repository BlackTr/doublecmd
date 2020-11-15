#!/bin/sh

export REVISION_INC=$1/dcrevision.inc

rm -f $REVISION_INC
cp ../units/dcrevision.inc $REVISION_INC

export REVISION=$(svnversion ../ | sed -e 's/\([0-9]*\).*/\1/')

if [ ! -z $REVISION ]; then
	echo "// Created by Svn2RevisionInc"    >  $REVISION_INC
  	echo "const dcRevision = '$REVISION';"  >> $REVISION_INC
	echo "Subversion revision" $REVISION
else
	REVISION=$(git log -1 --format="%h")
	if [ ! -z $REVISION ]; then
		echo "// Created by Git2RevisionInc"    >  $REVISION_INC
	  	echo "const dcRevision = '$REVISION';"  >> $REVISION_INC
		echo "Git revision" $REVISION
	fi
fi
