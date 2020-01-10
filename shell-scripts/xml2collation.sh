#!/usr/bin/env bash

#  Container version of IRSB-integrator.sh
#  From transcription to collation (xml > xmlwf > uconv > tpe2tei > collatex).
#  Container is a ubuntu image with Java and Python 3 installed.
#
#
#  Created by Violeta on 13.11.2019


#check arguments
if [[ ($# -lt 2) || ($# -ge 3 && $3 != "-m" ) ]]
then
    printf "Usage:\tinputfolder outputfolder [-m]"
    printf "\n\tinputfolder \t-- path to XML transcription files"
    printf "\n\toutputfolder \t-- path to destination folder (twill be generated if needed)"
    printf "\n\toptionnal -m flag \t-- treat milestones one by one"
    exit 0
fi

export INPUT=$1

export OUTPUT=$2
if [ -d "$OUTPUT" ]; then rm -rf $OUTPUT; fi
mkdir $OUTPUT

export MST_FLAG=""
if [ ! -z "$3" ] # not empty
  then export MST_FLAG=$3
fi

# path to tools/resources
export TPEN2TEI_PATH=(/tpen2tei)
export NORM_MOD=($TPEN2TEI_PATH/Milestones.Milestones) #Milestones/Milestones.py
export COLLATEX=(/collatex/collatex-tools/target/collatex-tools-1.8-SNAPSHOT.jar) # collatex jar
MILESTONE_FILE="milestones.csv"
ABBR_FILE="abbr.csv"
STEMMAREST_URL=(http://stemmarest:8080/stemmarest)

printf "\nInput directory:" $INPUT

if find $INPUT -name "*.xml" | wc -l | grep -qw "0";
then
    printf "\nNo XML files found."
    exit 0
else
    printf "\n`find $INPUT -name "*.xml" | wc -l` XML files found."
fi

if [ ! -d "$OUTPUT/1-wf/" ]; then mkdir $OUTPUT/1-wf/; else rm $OUTPUT/1-wf/*; fi
if [ ! -d "$OUTPUT/1-nwf/" ]; then mkdir $OUTPUT/1-nwf/; else rm $OUTPUT/1-nwf/*; fi
if [ ! -d "$OUTPUT/2-pre/" ]; then mkdir $OUTPUT/2-pre/; else rm $OUTPUT/2-pre/*; fi

# XMLWF
printf "\n\nChecking well-formedness..."
for file in `find $INPUT -name "*.xml"`
do
    if xmlwf $file | wc -l | grep -qw "0"; #well-formed
    then
        cp $file $OUTPUT/1-wf/
        cp $file $OUTPUT/2-pre/
    else
        cp $file $OUTPUT/1-nwf/
    fi
done
printf "\n`find $OUTPUT/1-wf/ -name "*.xml" | wc -l` well-formed files found\n"
ls $OUTPUT/1-wf/

printf "\n`find $OUTPUT/1-nwf/ -name "*.xml" | wc -l` ill-formed files found\n"
ls $OUTPUT/1-nwf/

# UCONV
printf "\nUnicode normalization...\n"
for file in `ls $OUTPUT/1-wf/`
do
    # printf "uconv -x any-nfc -f UTF-8 -o tmpuconv $OUTPUT/1-wf/$file && mv tmpuconv $OUTPUT/1-wf/$file"
    uconv -x any-nfc -f UTF-8 -o tmpuconv $OUTPUT/1-wf/$file && mv tmpuconv $OUTPUT/1-wf/$file
done

#TPEN2TEI
printf "\nPre-processing XML files..."

printf "\n\tRemoving DOCTYPE declaration"
for file in `ls $OUTPUT/1-wf/`
do
    #printf $file
    sed -i '/DOCTYPE/d' $OUTPUT/2-pre/$file
    printf "."
done

printf "\n\tAdding namespace declaration"
for file in `ls $OUTPUT/2-pre/`
do
    #printf $file
    #sed -i 's/<TEI>/<TEI xmlns=\"http://www.tei-c.org/ns/1.0\">/'  $OUTPUT/2-pre/$file
    awk 'NR==2 {$0="<TEI xmlns=\"http://www.tei-c.org/ns/1.0\">"} 1' $OUTPUT/2-pre/$file > tmpfile && mv tmpfile $OUTPUT/2-pre/$file
    printf "."
done

# artificially add a blank to mark the end of the word,
# whenever the transcribed line ends with <lb> (and is not followed by word continuation)
printf "\n\tInserting space between words separated by lb and newline (word pb|cb? lb newline)"
for file in `ls $OUTPUT/2-pre/`
do
  sed -r -i 's/([^ ])(<pb .*\/> *<lb n="[[:alnum:]]*" *\/>$)/\1 \2/g' $OUTPUT/2-pre/$file # word pb lb newline: add space after word
  sed -r -i 's/([^ ])(<cb .*\/> *<lb n="[[:alnum:]]*" *\/>$)/\1 \2/g' $OUTPUT/2-pre/$file # word cb lb newline: add space after word
  sed -r -i 's/([^ ])(<lb n="[[:alnum:]]*" *\/>$)/\1 \2/g' $OUTPUT/2-pre/$file # word lb newline: add space after word
  sed -r -i 's/([^ ])(<lb n="[[:alnum:]]*" *\/>)\s/\1 \2/g' $OUTPUT/2-pre/$file # word lb space: move space after word
  printf "."
done

printf "\n\tSame (between word & newline lb)"
for file in `ls $OUTPUT/2-pre/`
do
  sed -r -i 's/(^<lb\/>)/ \1/g' $OUTPUT/2-pre/$file # newline lb : insert space before lb
  sed -r -i 's/(^<lb n=".*" *\/>)/ \1/g' $OUTPUT/2-pre/$file # same, when lb has n attribute
  printf "."
done


if [ ! -f $ABBR_FILE ]
then
  printf "Resetting abbreviation file"
  cp /tpen2tei/Milestones/abbr.csv .
fi

if [ "$MST_FLAG" == "-m" ]
then
  if [ ! -f $MILESTONE_FILE ] # milestone file does not exists
  then
      printf "\n\nAutomatically retrieving milestones list..."
      for file in `ls $OUTPUT/2-pre/`
      do
        sed -n 's/.*milestone n="\([^"]*\).*/\1/p'  $OUTPUT/2-pre/$file >> $MILESTONE_FILE
      done
      sort -u -o $MILESTONE_FILE $MILESTONE_FILE
  fi

  if [ -s $MILESTONE_FILE ]
  then
    printf "\nMilestones found: `cat $MILESTONE_FILE | wc -l | xargs`" # xargs to remove spaces
  else
    printf "No milestone found."
    $MST_FLAG = ""
  fi
fi

if [ ! -d "$OUTPUT/3-collatex-input/" ]; then mkdir $OUTPUT/3-collatex-input/; else rm $OUTPUT/3-collatex-input/*; fi
if [ "$MST_FLAG" == "-m" ]
then
  # printf "\n\tMilestone creation and tokenization using teixml2collatex.py..."
  printf "\n\nRunning TEIXML2COLLATEX...\n"
  python3 $TPEN2TEI_PATH/teixml2collatex.py $OUTPUT/2-pre/ $OUTPUT/3-collatex-input/ -c $NORM_MOD

  printf "\nMILESTONES (JSON): `ls -l $OUTPUT/3-collatex-input/milestone* | wc -l | xargs` (See $OUTPUT/3-collatex-input/)\n"
fi
ls -l $OUTPUT/3-collatex-input/*.json

#COLLATEX
printf "\nRunning CollateX"
if [ "$MST_FLAG" == "-m" ]
then
  printf " (milestone by milestone)"
fi
printf "..."

if [ ! -d "$OUTPUT/4-collations" ]; then mkdir $OUTPUT/4-collations/; else rm $OUTPUT/4-collations/*; fi

for file in `ls $OUTPUT/3-collatex-input/`
do
  # -t for token by token: -t -f json >
  java -jar -Dnashorn.args="--no-deprecation-warning" $COLLATEX $OUTPUT/3-collatex-input/$file -t -f json > $OUTPUT/4-collations/collation-$file
  if [ "$MST_FLAG" == "-m" ]; then printf "."; fi
done
printf "\n\tFiles (JSON): `ls -l $OUTPUT/4-collations/collation* | wc -l | xargs` (See $OUTPUT/4-collations/)\n"
ls -l $OUTPUT/4-collations/*

echo "\nUploading collations to Stemmaweb ($STEMMAREST_URL)..."
#create user
curl --request PUT --header "Content-Type: application/json" --data '{ "role": "user", "id":"user@example.org", "email":"user@example.org", "passphrase":"d0d4f76c2ba30e1eb0bdfe544df5ec8e6951872106eb1bd3d7f9208993f28c69" }' $STEMMAREST_URL/user/user@example.org

#create tradition (output folder name)
TRADITION_NAME="auto_docker_$(basename $OUTPUT)"
curl --request POST --form "name=$TRADITION_NAME" --form "public=no" --form "userId=user@example.org" --form "empty=no" $STEMMAREST_URL/tradition > create-tradition.response

TRADITION_ID=`jq ".tradId" create-tradition.response | sed s/\"//g`

#upload collations (JSON format)
echo ""
for i in `ls $OUTPUT/4-collations/*.json`
do
  SECTION_NAME=$(basename $i)
  # echo "curl --request POST --form "name=$SECTION_NAME" --form "file=@$i" --form "filetype=cxjson" $STEMMAREST_URL/tradition/$TRADITION_ID/section;"
  curl --request POST --form "name=$SECTION_NAME" --form "file=@$i" --form "filetype=cxjson" $STEMMAREST_URL/tradition/$TRADITION_ID/section;
done

printf "To see the results, login to localhost:3000 with user@example.org/UserPass"
