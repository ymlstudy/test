1，HPA VPA CA是什么：
水平pod自动缩放器(HPA)：
 基于pod 资源利用率横向调整pod副本数量。
 VPA是动态膨胀成为一个资源上限更大的Pod。

垂直pod自动缩放器(VPA)：
 基于pod资源利用率，调整对单个pod的最大资源限制，
不能与HPA同时使用。
 HPA是动态裂变成数量更多的Pod

集群伸缩(Cluster Autoscaler,CA)
 基于集群中node 资源使用情况，动态伸缩node节点，
从而保证有CPU和内存资源用于创建pod。
 CA是动态扩横向容更多的底层IAAS资源
 



例子1-缩容：
#十个pod，当前累计使用330%、平均33%、阈值60%，则缩容计算公式如下：
期望副本数=(10(当前副本数)*((33%(当前deployment 下的pod指标全部相加，此处为故意写每个pod 33%)*10)/ (60%(阈值)*10(当前副本数))))
期望副本数=10*(330/600)
期望副本数=10*(0.55) #0.55 ≤ 0.9 && ≥ 1.1，不大于等于1.1、但是小于等于0.9，缩容条件成立、则进行缩容
期望副本数=5.5(向上取整数、目标pod调整为6个=缩容4个pod)

例子2-扩容：
#三个pod，当前累计使用270%、平均90%、阈值60%, 则扩容公式如下:
期望副本数=(3(当前副本数)*((90%当前deployment 下的pod指标全部相加，此处为故意写的每个pod 90%)*3)/(60%(阈值)**3)))
期望副本数=3*（270/180）
期望副本数=3*1.5 #1.5 ≤ 0.9 && ≥ 1.1 #不小于0.9但是大于等于1.1，扩容条件成立
期望副本数=4.5(目标副本调整为5个=扩容两个新的pod)

记住的方法：
新副本 = 当前副本 × 当前利用率 ÷ 目标利用率（向上取整）

2，Prometheus Adapter 
作用是把 Prometheus 里的监控指标转换成 Kubernetes API，让 HPA（Horizontal Pod Autoscaler）能够使用自定义指标进行自动扩缩容。

Prometheus Adapter 是 Kubernetes 官方提供的聚合 API 组件，用于将 Prometheus 中的监控指标通过 custom.metrics.k8s.io 或 external.metrics.k8s.io 暴露给 Kubernetes。HPA 可以基于这些自定义指标（如 HTTP QPS、Kafka Lag、RabbitMQ 队列长度等）进行自动扩缩容，而不仅仅局限于 CPU 和内存。它本身不存储监控数据，只负责从 Prometheus 查询指标并转换成 Kubernetes 能识别的 Metrics API。



3，Metrics Server :
是 Kubernetes 内置的容器资源指标来源, Metrics Server 从node节点上的 Kubelet 收集资源指标,并通过Metrics API在Kubernetesapiserver中公开指标数据,以供 Horizontal Pod Autoscaler和Vertical Pod Autoscaler使用,也可以通过访问kubectl top 

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml

解决报错：
kubectl edit deployment metrics-server -n kube-system
args:
- --cert-dir=/tmp
- --secure-port=10250
- --metric-resolution=15s
- --kubelet-preferred-address-types=InternalIP,Hostname,ExternalIP
- --kubelet-use-node-status-port
- --kubelet-insecure-tls #这行加上





4，Prometheus Adapter部署安装
https://github.com/kubernetes-sigs/prometheus-adapter/tree/master
git clone -b release-0.10 https://github.com/kubernetes-sigs/prometheus-adapter.git
cd /prometheus-adapter/deploy

export PURPOSE=serving
openssl req -x509 -sha256 -new -nodes -days 365 -newkey rsa:2048 -keyout ${PURPOSE}-ca.key -out ${PURPOSE}-ca.crt -subj "/CN=ca"

openssl req -newkey rsa:2048 -nodes -keyout serving.key -x509 -days 365 -out serving.crt \
-subj "/CN=custom-metrics-apiserver"

echo '{"signing":{"default":{"expiry":"43800h","usages":["signing","key encipherment","'${PURPOSE}'"]}}}' > "${PURPOSE}-ca-config.json"

kubectl create secret generic cm-adapter-serving-certs -n monitoring \
--from-file=./serving.crt \
--from-file=./serving.key

sed -i 's/namespace: custom-metrics/namespace: monitoring/g' manifests/*.yaml

kubectl apply -f manifests/
kubectl get pods -n monitoring |grep custom-metrics
k apply -f yaml/
kubectl get hpa -n myserver 
NAME                    REFERENCE                      TARGETS           MINPODS   MAXPODS   REPLICAS   AGE
sample-httpserver-hpa   Deployment/sample-httpserver   375m/1            2         10        2          52m
tomcat-deployment-hpa   Deployment/tomcat-deployment   275999m/512001m   2         10        2          70m

观察pod副本的动态变化：
watch -n 1 "kubectl get hpa -n myserver "

