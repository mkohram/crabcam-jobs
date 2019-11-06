#!/usr/bin/env bash

S3_PREFIX="s3://crabcam"
S3_READ="$S3_PREFIX/videos"
S3_WRITE="$S3_PREFIX/public"
LATEST_PROCESSED=`/usr/local/bin/aws s3 ls $S3_PREFIX/processed/ | tail -n1 | tr -s ' ' | cut -d' ' -f4`

NOW=`date +%s`
STAGING_DIR=`mktemp -d /tmp/crabcam-staging-$NOW-XXXXXXXX`
TMP_LIST_FILE="$STAGING_DIR/list.txt"
YT_TITLE=`TZ=America/New_York date`

while read line; do 
  FILENAME=`echo $line | tr -s ' ' | cut -d' ' -f4`; 
  TIMESTAMP=`echo $FILENAME | cut -d'-' -f1` 
 
  if [[ "$TIMESTAMP" > "$LATEST_PROCESSED" ]]; then
    /usr/local/bin/aws s3 cp "$S3_READ/$FILENAME" "$STAGING_DIR/$FILENAME"
    echo file \'$STAGING_DIR/$FILENAME\' >> $TMP_LIST_FILE
    MAX_TIMESTAMP=$TIMESTAMP
  fi
done < <(/usr/local/bin/aws s3 ls $S3_READ/)

OUTPUT_FILE="$STAGING_DIR/$MAX_TIMESTAMP.mp4" 
if [[ -f $TMP_LIST_FILE ]]; then
  ffmpeg -f concat -safe 0 -i $TMP_LIST_FILE -filter:v "setpts=0.1*PTS" -c:a copy -an $OUTPUT_FILE && \
    /usr/local/bin/aws s3 cp $OUTPUT_FILE "$S3_WRITE/$OUTPUTFILE" && \
    echo '' > "$STAGING_DIR/$MAX_TIMESTAMP" && \
    python3 /home/ubuntu/crabcam-jobs/upload_video.py --file $OUTPUT_FILE --title "$YT_TITLE" --description "8 hour digest" --privacyStatus public > $STAGING_DIR/yt.log && \
    YT_ID=`cat $STAGING_DIR/yt.log | grep 'video_id' | cut -d'|' -f2` && \
    >&2 echo "Waiting for youtube to process ..." && \
    sleep 60 && \
    curl -sX POST -H 'Content-type: application/json' --data "{\"text\": \"new video at: https://www.youtube.com/watch?v=${YT_ID}\", \"icon_emoji\": \":hermes:\"}" ${SLACK_HOOK} &> /dev/null && \
    /usr/local/bin/aws s3 cp "$STAGING_DIR/$MAX_TIMESTAMP" $S3_PREFIX/processed/ || >&2 echo "Something failed"
else
  >&2 echo "no new files to process"
fi

rm -rf $STAGING_DIR
