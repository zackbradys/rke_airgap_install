#!/bin/bash

set -ebpf

export RKE_VERSION=v1.23.4
export CERT_VERSION=v1.7.2
export RANCHER_VERSION=v2.6.4

mkdir -p /output/rke2/
cd /output/rke2/

echo - download rke, rancher and longhorn
curl -#OL https://github.com/rancher/rke2/releases/download/$RANCHER_VERSION%2Brke2r2/rke2-images.linux-amd64.tar.zst
curl -#OL https://github.com/rancher/rke2/releases/download/$RANCHER_VERSION%2Brke2r2/rke2.linux-amd64.tar.gz
curl -#OL https://github.com/rancher/rke2/releases/download/$RANCHER_VERSION%2Brke2r2/sha256sum-amd64.txt

echo - get the install script
curl -sfL https://get.rke2.io --output install.sh

echo - Get Helm Charts

echo - create helm dir
mkdir -p /output/helm/
cd /output/helm/

echo - get helm
curl -#L https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo - add repos
helm repo add jetstack https://charts.jetstack.io
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo add longhorn https://charts.longhorn.io
helm repo update

echo - get charts
helm pull jetstack/cert-manager --version $CERT_VERSION
helm pull rancher-latest/rancher
helm pull longhorn/longhorn

echo - get the cert-manager crt
curl -#LO https://github.com/jetstack/cert-manager/releases/download/$CERT_VERSION/cert-manager.crds.yaml

echo - Get Images - Rancher/Longhorn

echo - create image dir
mkdir -p /output/images/{cert,rancher,longhorn}
cd /output/images/

echo - rancher image list 
curl -#L https://github.com/rancher/rancher/releases/download/$RANCHER_VERSION/rancher-images.txt -o rancher/orig_rancher-images.txt

echo - shorten rancher list with a sort
sed -i -e '0,/busybox/s/busybox/library\/busybox/' -e 's/registry/library\/registry/g' rancher/orig_rancher-images.txt
for i in $(cat rancher/orig_rancher-images.txt|awk -F: '{print $1}'); do 
  grep -w $i rancher/orig_rancher-images.txt | sort -Vr| head -1 >> rancher/version_unsorted.txt
done
grep -x library/busybox rancher/orig_rancher-images.txt | sort -Vr| head -1 > rancher/rancher-images.txt
cat rancher/version_unsorted.txt | sort -u >> rancher/rancher-images.txt

echo - We need to add the cert-manager images
helm template /output/helm/cert-manager-$CERT_VERSION.tgz | awk '$1 ~ /image:/ {print $2}' | sed s/\"//g > cert/cert-manager-images.txt

echo - longhorn image list
curl -#L https://raw.githubusercontent.com/longhorn/longhorn/v1.2.4/deploy/longhorn-images.txt -o longhorn/longhorn-images.txt

echo - skopeo cert-manager
for i in $(cat cert/cert-manager-images.txt); do 
  skopeo copy docker://$i docker-archive:cert/$(echo $i| awk -F/ '{print $3}'|sed 's/:/_/g').tar:$(echo $i| awk -F/ '{print $3}') 
done

echo - skopeo - longhorn
for i in $(cat longhorn/longhorn-images.txt); do 
  skopeo copy docker://$i docker-archive:longhorn/$(echo $i| awk -F/ '{print $2}'|sed 's/:/_/g').tar:$(echo $i| awk -F/ '{print $2}') 
done

echo - skopeo - Rancher - This will take time getting all the images
for i in $(cat rancher/rancher-images.txt); do 
  skopeo copy docker://$i docker-archive:rancher/$(echo $i| awk -F/ '{print $2}'|sed 's/:/_/g').tar:$(echo $i| awk -F/ '{print $2}') &
done


echo - Get Nerdctl
mkdir -p /output/nerdctl/
cd /output/nerdctl/
curl -#LO https://github.com/containerd/nerdctl/releases/download/v0.18.0/nerdctl-0.18.0-linux-amd64.tar.gz


cd /output
echo - compress all the things
tar -zvcf /output/rke2_rancher_longhorn.tgz helm rke2 images nerdctl
