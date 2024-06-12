# PURPOSE: This Dockerfile will prepare an Amazon Linux docker image with everything needed to compile binary MediaInfo libraries for Python 3.7 and Python 3.8
# USAGE: 
# 1. Build the docker image:
#     docker build --tag=pymediainfo-layer-factory:latest .
# 2. Build and copy MediaInfo libraries to ./pymediainfo-python[37,38].zip
#     docker run --rm -it -v $(pwd):/data pymediainfo-layer-factory cp /packages/pymediainfo-python37.zip /data

FROM amazonlinux:2022

WORKDIR /
RUN yum update -y
RUN yum install gcc gcc-c++ openssl-devel bzip2-devel libffi-devel wget tar gzip zip make zlib-devel -y

WORKDIR /
RUN wget https://www.python.org/ftp/python/3.12.0/Python-3.12.0.tgz
RUN tar -xzf Python-3.12.0.tgz
WORKDIR /Python-3.12.0
RUN ./configure --enable-optimizations
RUN make install

RUN mkdir /packages
RUN echo "pymediainfo" >> /packages/requirements.txt

RUN mkdir -p /packages/pymediainfo-3.12/python/lib/python3.12/site-packages
RUN pip3.12 install importlib-metadata

RUN pip3.12 install -r /packages/requirements.txt -t /packages/pymediainfo-3.12/python/lib/python3.12/site-packages

WORKDIR /root
RUN wget https://mediaarea.net/download/binary/libmediainfo0/19.09/MediaInfo_DLL_19.09_GNU_FromSource.tar.gz
RUN tar -xzvf MediaInfo_DLL_19.09_GNU_FromSource.tar.gz

WORKDIR /root/MediaInfo_DLL_GNU_FromSource/
RUN ./SO_Compile.sh

RUN cp /root/MediaInfo_DLL_GNU_FromSource/MediaInfoLib/Project/GNU/Library/.libs/* /packages/pymediainfo-3.12/python
RUN cp /root/MediaInfo_DLL_GNU_FromSource/MediaInfoLib/Project/GNU/Library/.libs/* /packages/pymediainfo-3.12/
WORKDIR /packages/pymediainfo-3.12/
RUN zip -r9 /packages/pymediainfo-python312.zip .
WORKDIR /packages/
RUN rm -rf /packages/pymediainfo-3.12/
