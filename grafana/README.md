## 📊 **Kubernetes Monitoring Setup with Prometheus & Grafana**

This project provides a monitoring stack for Kubernetes clusters using **Prometheus**, **Grafana**, **kube-state-metrics**, **node-exporter**, and **Pushgateway** — all deployed via Helm charts.



## 📦 **Components Included**

- **Prometheus**: Time-series metrics collection.
- **Prometheus Node Exporter**: Exposes node-level metrics.
- **Prometheus Pushgateway**: Allows ephemeral jobs to push metrics.
- **Kube State Metrics**: Exposes cluster state metrics (deployments, pods, etc.)
- **Grafana**: Dashboards for visualizing collected metrics.
- **ServiceMonitor**: Enables custom metric scraping within Kubernetes via the Prometheus Operator.

-------

## 📜 **Prometheus Configuration Highlights** via values-agent.yaml file

- **Scrape Interval**: `15s`
- **Evaluation Interval**: `15s`
- **External Labels**: Cluster labeled as `attendee-staging`
- **Remote Write**: Enabled to send metrics to an external Prometheus server  
  `http://Public IP of centralized promethues server :9090/api/v1/write`

-------

## 📊 **Grafana Dashboard** using grafana-dashboard.json file

A predefined **Grafana dashboard JSON** is included:

- **Path**: `grafana-dashboard.json`
- **Contains panels and queries for**:
  - Cluster resource usage
  - Node metrics
  - Workload health
  - Custom Prometheus queries

**Import this JSON into Grafana via the Import Dashboard option.**

-------

## **Install Prometheus Agent with Custom Values**

-- kubectl create namespace monitoring 

-- helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

-- helm repo update

-- helm install attendee-prom-agent prometheus-community/prometheus \ --namespace monitoring -f values-agent.yaml 

-- kubectl get pods -n monitoring

-- kubectl get svc -n monitoring 

-------

## ⚙️ **Modified Files in Centralized Prometheus Server**

We made changes to **two files** in the centralized Prometheus server to support remote writes and set storage paths/limits.

*sudo nano /etc/systemd/system/prometheus.service* 

[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/opt/prometheus/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/mnt/prometheus-data/ \
  --storage.tsdb.retention.time=15d \
  --storage.tsdb.retention.size=2GB \
  --storage.tsdb.max-block-duration=2h \
  --query.max-concurrency=5 \
  --web.enable-remote-write-receiver

[Install]
WantedBy=multi-user.target

*sudo nano /etc/prometheus/prometheus.yml* 

global:
  scrape_interval: 30s
  evaluation_interval: 30s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090'] 

*restart the prometheus*

-- sudo systemctl daemon-reload 

-- sudo systemctl restart prometheus

-- sudo systemctl status prometheus

------- 












