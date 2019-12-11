# AWS Lambda function for MediaInfo

This project illustrates how to create an AWS Lambda function using Python 3.7 and [MediaInfo](https://mediaarea.net/en/MediaInfo) to get metadata and tag data for a video file stored in AWS S3. The Python MediaInfo library can be published together with the application code as an all-in-one Lambda function, or as a Lambda layer which reduces the size of the Lambda function and enables the function code to be displayed in the Lambda code viewer in the AWS console. Both deploy options are described in USAGE. Option #1 results in a 1MB Lambda package and Option #2 is 716 bytes. They look like this in the AWS Lambda console:

![images/lambda_function_sizes.png](images/lambda_function_sizes.png)

Sample output from these Lambda functions is shown [here](https://gist.github.com/iandow/7cd0ae84ad69f8fd993733903807bfe3).

## USAGE:

### Preliminary AWS CLI Setup: 
1. Install [Docker](https://docs.docker.com/), the [AWS CLI](https://aws.amazon.com/cli/), and [jq](https://stedolan.github.io/jq/) on your workstation.
2. Setup credentials for AWS CLI (see http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html).
3. Create IAM Role with Lambda and S3 access:
```
# Create a role with S3 and Lambda exec access
ROLE_NAME=lambda-pymediainfo_study
aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document '{"Version":"2012-10-17","Statement":{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}}'
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess --role-name $ROLE_NAME
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole --role-name $ROLE_NAME
```

### Build MediaInfo library using Docker

AWS Lambda functions run in an [Amazon Linux environment](https://docs.aws.amazon.com/lambda/latest/dg/current-supported-versions.html), so libraries should be built for Amazon Linux. You can build `libmediainfo.so` libraries for Amazon Linux using the provided Dockerfile, like this:

```
git clone https://github.com/iandow/mediainfo_aws_lambda
cd mediainfo_aws_lambda
docker build --tag=pymediainfo-layer-factory:latest .
docker run --rm -it -v $(pwd):/data pymediainfo-layer-factory cp /packages/pymediainfo-python37.zip /data
```

### Deploy Option #1 - Lambda function with dependencies included.

***NOTE! [Deploy Option #2](https://github.com/iandow/mediainfo_aws_lambda#deploy-option-2-preferred---lambda-function-with-libraries-as-lambda-layers) is better. Do that one.***

1. Edit the Lambda function code to do whatever you want it to do.
```
vi app.py
```

2. Combine Python libraries and app.py into a single all-in-one ZIP file
```
ZIPFILE=allinone.zip
unzip pymediainfo-python37.zip 
cp app.py python/lib/python3.7/site-packages/
cd python/lib/python3.7/site-packages/
zip -r9 ../../../../$ZIPFILE .
cd -
```

3. Deploy the Lambda function:
```
# Upload a test video
BUCKET_NAME=pymediainfo-test
aws s3 mb s3://$BUCKET_NAME
wget https://vjs.zencdn.net/v/oceans.mp4
S3_KEY=videos/oceans.mp4
aws s3 cp oceans.mp4 s3://$BUCKET_NAME/videos/
# Create the Lambda function:
FUNCTION_NAME=pymediainfo_allinone
ACCOUNT_ID=$(aws sts get-caller-identity | jq -r ".Account")
aws s3 cp $ZIPFILE s3://$BUCKET_NAME
aws lambda create-function --function-name $FUNCTION_NAME --timeout 10 --role arn:aws:iam::${ACCOUNT_ID}:role/$ROLE_NAME --handler app.lambda_handler --region us-west-2 --runtime python3.7 --environment "Variables={BUCKET_NAME=$BUCKET_NAME,S3_KEY=$S3_KEY}" --code S3Bucket="$BUCKET_NAME",S3Key="$ZIPFILE"
```

The problem with the all-in-one approach is that it results in a larger zip file. In this case, allinone.zip is 1MB. If it exceeds 3MB then you won't be able to use the code editor in the AWS Lambda web user interface on http://console.aws.amazon.com/lambda/. So, if you plan on adding any other packages to the deployable zip, then use Option #2, described below. It deploys pymediainfo as a lambda layer, and therefore results in a much smaller zip file.

### Deploy Option #2 (preferred) - Lambda function with libraries as Lambda layers.

1. Edit the Lambda function code to do whatever you want it to do.
```
vi app.py
```

2. Publish the `pymediainfo` Python library as a Lambda layer.
```
ACCOUNT_ID=$(aws sts get-caller-identity | jq -r ".Account")
LAMBDA_LAYERS_BUCKET=lambda-layers-$ACCOUNT_ID
LAYER_NAME=pymediainfo
aws s3 mb s3://$LAMBDA_LAYERS_BUCKET
aws s3 cp pymediainfo-python37.zip s3://$LAMBDA_LAYERS_BUCKET
aws lambda publish-layer-version --layer-name $LAYER_NAME --description "pymediainfo" --content S3Bucket=$LAMBDA_LAYERS_BUCKET,S3Key=pymediainfo-python37.zip --compatible-runtimes python3.7
```

3. Create the Lambda function:
```
zip app.zip app.py
```

4. Deploy the Lambda function:
```
BUCKET_NAME=pymediainfo-test
aws s3 mb s3://$BUCKET_NAME
# Upload a test video
wget https://vjs.zencdn.net/v/oceans.mp4
S3_KEY=videos/oceans.mp4
aws s3 cp oceans.mp4 s3://$BUCKET_NAME/videos/
# Create the Lambda function:
FUNCTION_NAME=pymediainfo_layered
ACCOUNT_ID=$(aws sts get-caller-identity | jq -r ".Account")
aws s3 cp app.zip s3://$BUCKET_NAME
aws lambda create-function --function-name $FUNCTION_NAME --timeout 20 --role arn:aws:iam::${ACCOUNT_ID}:role/$ROLE_NAME --handler app.lambda_handler --region us-west-2 --runtime python3.7 --environment "Variables={BUCKET_NAME=$BUCKET_NAME,S3_KEY=$S3_KEY}" --code S3Bucket="$BUCKET_NAME",S3Key="app.zip"
```

7. Attach the `pymediainfo` Lambda layer to our Lambda function:
```
LAYER=$(aws lambda list-layer-versions --layer-name $LAYER_NAME | jq -r '.LayerVersions[0].LayerVersionArn')
aws lambda update-function-configuration --function-name $FUNCTION_NAME --layers $LAYER
```

### Test the Lambda function:
Our Lambda function requires an image as input. Copy an image to S3, like this:
```
wget https://vjs.zencdn.net/v/oceans.mp4
aws s3 cp ./oceans.mp4 s3://$BUCKET_NAME/videos/oceans.mp4
```
Then invoke the Lambda function:
```
aws lambda invoke --function-name $FUNCTION_NAME --log-type Tail outputfile.txt
```

You should see output like this:
```
{
    "LogResult": "U1RBUlQgU..."
    "ExecutedVersion": "$LATEST",
    "StatusCode": 200
}
```

### Sample Output

The outputfile.txt will contain metadata values for the oceans.mp4 video file, like this:
(I added line breaks in the json below, to make it more readable.)
```
{
  "tracks": [
    {
      "track_type": "General",
      "count": "331",
      "count_of_stream_of_this_kind": "1",
      "kind_of_stream": "General",
      "other_kind_of_stream": [
        "General"
      ],
      "stream_identifier": "0",
      "count_of_video_streams": "1",
      "count_of_audio_streams": "1",
      "video_format_list": "AVC",
      "video_format_withhint_list": "AVC",
      "codecs_video": "AVC",
      "audio_format_list": "AAC LC",
      "audio_format_withhint_list": "AAC LC",
      "audio_codecs": "AAC LC",
      "complete_name": "/root/oceans.mp4",
      "folder_name": "/root",
      "file_name_extension": "oceans.mp4",
      "file_name": "oceans",
      "file_extension": "mp4",
      "format": "MPEG-4",
      "other_format": [
        "MPEG-4"
      ],
      "format_extensions_usually_used": "braw mov mp4 m4v m4a m4b m4p m4r 3ga 3gpa 3gpp 3gp 3gpp2 3g2 k3g jpm jpx mqv ismv isma ismt f4a f4b f4v",
      "commercial_name": "MPEG-4",
      "format_profile": "Base Media",
      "internet_media_type": "video/mp4",
      "codec_id": "isom",
      "other_codec_id": [
        "isom (isom/avc1)"
      ],
      "codec_id_url": "http://www.apple.com/quicktime/download/standalone.html",
      "codecid_compatible": "isom/avc1",
      "file_size": 23014356,
      "other_file_size": [
        "21.9 MiB",
        "22 MiB",
        "22 MiB",
        "21.9 MiB",
        "21.95 MiB"
      ],
      "duration": 46613,
      "other_duration": [
        "46 s 613 ms",
        "46 s 613 ms",
        "46 s 613 ms",
        "00:00:46.613",
        "00:00:46;12",
        "00:00:46.613 (00:00:46;12)"
      ],
      "overall_bit_rate_mode": "VBR",
      "other_overall_bit_rate_mode": [
        "Variable"
      ],
      "overall_bit_rate": 3949861,
      "other_overall_bit_rate": [
        "3 950 kb/s"
      ],
      "frame_rate": "23.976",
      "other_frame_rate": [
        "23.976 FPS"
      ],
      "frame_count": "1116",
      "stream_size": 16342,
      "other_stream_size": [
        "16.0 KiB (0%)",
        "16 KiB",
        "16 KiB",
        "16.0 KiB",
        "15.96 KiB",
        "16.0 KiB (0%)"
      ],
      "proportion_of_this_stream": "0.00071",
      "headersize": "16334",
      "datasize": "22998022",
      "footersize": "0",
      "isstreamable": "Yes",
      "encoded_date": "UTC 2013-05-03 22:51:07",
      "tagged_date": "UTC 2013-05-03 22:51:07",
      "file_last_modification_date": "UTC 2013-05-08 00:34:04",
      "file_last_modification_date__local": "2013-05-08 00:34:04"
    },
    {
      "track_type": "Video",
      "count": "378",
      "count_of_stream_of_this_kind": "1",
      "kind_of_stream": "Video",
      "other_kind_of_stream": [
        "Video"
      ],
      "stream_identifier": "0",
      "streamorder": "0",
      "track_id": 1,
      "other_track_id": [
        "1"
      ],
      "format": "AVC",
      "other_format": [
        "AVC"
      ],
      "format_info": "Advanced Video Codec",
      "format_url": "http://developers.videolan.org/x264.html",
      "commercial_name": "AVC",
      "format_profile": "Baseline@L3",
      "format_settings": "3 Ref Frames",
      "format_settings__cabac": "No",
      "other_format_settings__cabac": [
        "No"
      ],
      "format_settings__reference_frames": 3,
      "other_format_settings__reference_frames": [
        "3 frames"
      ],
      "internet_media_type": "video/H264",
      "codec_id": "avc1",
      "codec_id_info": "Advanced Video Coding",
      "duration": 46545,
      "other_duration": [
        "46 s 545 ms",
        "46 s 545 ms",
        "46 s 545 ms",
        "00:00:46.545",
        "00:00:46;12",
        "00:00:46.545 (00:00:46;12)"
      ],
      "bit_rate": 3859631,
      "other_bit_rate": [
        "3 860 kb/s"
      ],
      "maximum_bit_rate": 9263280,
      "other_maximum_bit_rate": [
        "9 263 kb/s"
      ],
      "width": 960,
      "other_width": [
        "960 pixels"
      ],
      "height": 400,
      "other_height": [
        "400 pixels"
      ],
      "sampled_width": "960",
      "sampled_height": "400",
      "pixel_aspect_ratio": "1.000",
      "display_aspect_ratio": "2.400",
      "other_display_aspect_ratio": [
        "2.40:1"
      ],
      "rotation": "0.000",
      "frame_rate_mode": "CFR",
      "other_frame_rate_mode": [
        "Constant"
      ],
      "frame_rate": "23.976",
      "other_frame_rate": [
        "23.976 (24000/1001) FPS"
      ],
      "framerate_num": "24000",
      "framerate_den": "1001",
      "frame_count": "1116",
      "color_space": "YUV",
      "chroma_subsampling": "4:2:0",
      "other_chroma_subsampling": [
        "4:2:0"
      ],
      "bit_depth": 8,
      "other_bit_depth": [
        "8 bits"
      ],
      "scan_type": "Progressive",
      "other_scan_type": [
        "Progressive"
      ],
      "bits__pixel_frame": "0.419",
      "stream_size": 22456564,
      "other_stream_size": [
        "21.4 MiB (98%)",
        "21 MiB",
        "21 MiB",
        "21.4 MiB",
        "21.42 MiB",
        "21.4 MiB (98%)"
      ],
      "proportion_of_this_stream": "0.97576",
      "writing_library": "Zencoder Video Encoding System",
      "other_writing_library": [
        "Zencoder Video Encoding System"
      ],
      "encoded_library_name": "Zencoder Video Encoding System",
      "encoded_date": "UTC 2013-05-03 22:50:47",
      "tagged_date": "UTC 2013-05-03 22:51:08",
      "codec_configuration_box": "avcC"
    },
    {
      "track_type": "Audio",
      "count": "280",
      "count_of_stream_of_this_kind": "1",
      "kind_of_stream": "Audio",
      "other_kind_of_stream": [
        "Audio"
      ],
      "stream_identifier": "0",
      "streamorder": "1",
      "track_id": 2,
      "other_track_id": [
        "2"
      ],
      "format": "AAC",
      "other_format": [
        "AAC LC"
      ],
      "format_info": "Advanced Audio Codec Low Complexity",
      "commercial_name": "AAC",
      "format_settings__sbr": "No (Explicit)",
      "other_format_settings__sbr": [
        "No (Explicit)"
      ],
      "format_additionalfeatures": "LC",
      "codec_id": "mp4a-40-2",
      "duration": 46613,
      "other_duration": [
        "46 s 613 ms",
        "46 s 613 ms",
        "46 s 613 ms",
        "00:00:46.613",
        "00:00:46:23",
        "00:00:46.613 (00:00:46:23)"
      ],
      "bit_rate_mode": "VBR",
      "other_bit_rate_mode": [
        "Variable"
      ],
      "bit_rate": 92920,
      "other_bit_rate": [
        "92.9 kb/s"
      ],
      "maximum_bit_rate": 104944,
      "other_maximum_bit_rate": [
        "105 kb/s"
      ],
      "channel_s": 2,
      "other_channel_s": [
        "2 channels"
      ],
      "channel_positions": "Front: L R",
      "other_channel_positions": [
        "2/0/0"
      ],
      "channel_layout": "L R",
      "samples_per_frame": "1024",
      "sampling_rate": 48000,
      "other_sampling_rate": [
        "48.0 kHz"
      ],
      "samples_count": "2237424",
      "frame_rate": "46.875",
      "other_frame_rate": [
        "46.875 FPS (1024 SPF)"
      ],
      "frame_count": "2185",
      "compression_mode": "Lossy",
      "other_compression_mode": [
        "Lossy"
      ],
      "stream_size": 541450,
      "other_stream_size": [
        "529 KiB (2%)",
        "529 KiB",
        "529 KiB",
        "529 KiB",
        "528.8 KiB",
        "529 KiB (2%)"
      ],
      "proportion_of_this_stream": "0.02353",
      "encoded_date": "UTC 2013-05-03 22:51:07",
      "tagged_date": "UTC 2013-05-03 22:51:08"
    }
  ]
}
```

### Clean up resources
```
aws s3 rm s3://$BUCKET_NAME/videos/oceans.mp4
aws s3 rb s3://$BUCKET_NAME/
aws s3 rm s3://$LAMBDA_LAYERS_BUCKET/pymediainfo-python37.zip
aws s3 rb s3://$LAMBDA_LAYERS_BUCKET
rm oceans.mp4
rm -rf ./app.zip ./python/
aws lambda delete-function --function-name $FUNCTION_NAME
LAYER_VERSION=$(aws lambda list-layer-versions --layer-name pymediainfo | jq -r '.LayerVersions[0].Version')
aws lambda delete-layer-version --layer-name pymediainfo --version-number $LAYER_VERSION
aws iam detach-role-policy --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole --role-name $ROLE_NAME
aws iam detach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess --role-name $ROLE_NAME
aws iam delete-role --role-name $ROLE_NAME
```

