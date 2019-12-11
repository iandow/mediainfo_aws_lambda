FROM amazonlinux

WORKDIR /
RUN yum update -y

# Install Python 3.
RUN yum -y install openssl-devel bzip2-devel libffi-devel wget tar gzip make gcc-c++
RUN wget https://www.python.org/ftp/python/3.8.0/Python-3.8.0.tgz
RUN tar -xzvf Python-3.8.0.tgz
WORKDIR /Python-3.8.0
RUN ./configure --enable-optimizations
RUN make install

# Install Python 3.7
RUN yum install python3 zip -y

# Install Python packages
RUN mkdir /packages
RUN echo "pymediainfo" >> /packages/requirements.txt
RUN mkdir -p /packages/pymediainfo-3.7/python/lib/python3.7/site-packages
RUN mkdir -p /packages/pymediainfo-3.8/python/lib/python3.8/site-packages
RUN pip3.7 install -r /packages/requirements.txt -t /packages/pymediainfo-3.7/python/lib/python3.7/site-packages
RUN pip3.8 install -r /packages/requirements.txt -t /packages/pymediainfo-3.8/python/lib/python3.8/site-packages

# Build libmediainfo library
WORKDIR /root
RUN wget https://mediaarea.net/download/binary/libmediainfo0/19.09/MediaInfo_DLL_19.09_GNU_FromSource.tar.gz
RUN tar -xzvf MediaInfo_DLL_19.09_GNU_FromSource.tar.gz
WORKDIR /root/MediaInfo_DLL_GNU_FromSource/
RUN bash SO_Compile.sh
RUN cp /root/MediaInfo_DLL_GNU_FromSource/MediaInfoLib/Project/GNU/Library/.libs/* /packages/pymediainfo-3.7/
RUN cp /root/MediaInfo_DLL_GNU_FromSource/MediaInfoLib/Project/GNU/Library/.libs/* /packages/pymediainfo-3.8/

# Create zip files for Lambda Layer deployment
WORKDIR /packages/pymediainfo-3.7/
RUN zip -r9 /packages/pymediainfo-python37.zip .
WORKDIR /packages/pymediainfo-3.8/
RUN zip -r9 /packages/pymediainfo-python38.zip .
WORKDIR /packages/
RUN rm -rf /packages/pymediainfo-3.7/
RUN rm -rf /packages/pymediainfo-3.8/
