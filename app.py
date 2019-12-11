import json
import logging
import boto3
import botocore
import os
from pymediainfo import MediaInfo

def lambda_handler(event, context):
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)
    logger.info('event parameter: {}'.format(event))
    tmp_filename='/tmp/oceans.mp4'

    s3 = boto3.resource('s3')
    BUCKET_NAME = os.environ.get("BUCKET_NAME")
    S3_KEY = os.environ.get("S3_KEY")
        
    try:
        s3.Bucket(BUCKET_NAME).download_file(S3_KEY, tmp_filename)
    except botocore.exceptions.ClientError as e:
        if e.response['Error']['Code'] == "404":
            print("The object does not exist: s3://" + BUCKET_NAME + S3_KEY)
        else:
            raise

    media_info = MediaInfo.parse(tmp_filename, library_file='/opt/libmediainfo.so.0')

    print(str(media_info.to_json()))

    for track in media_info.tracks:
        if track.track_type == 'Video':
            print("track info: " + str(track.bit_rate) + " " + str(track.bit_rate_mode)  + " " + str(track.codec))

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": str(media_info.to_json())
        }),
    }

