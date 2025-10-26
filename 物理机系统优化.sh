#!/bin/bash

# 物理机系统优化脚本 - 为高并发Web服务器优化Linux系统参数

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "======================================"
echo "TinyWebServer 物理机系统优化脚本"
echo "======================================"
echo ""

# 检查是否有root权限
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请使用 sudo 运行此脚本${NC}"
    echo "用法: sudo ./物理机系统优化.sh"
    exit 1
fi

echo -e "${BLUE}步骤1: 备份原始配置${NC}"
echo "======================================"

# 备份sysctl配置
BACKUP_DIR="/root/sysctl_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR
cp /etc/sysctl.conf $BACKUP_DIR/
echo -e "${GREEN}✓ 已备份到 $BACKUP_DIR${NC}"
echo ""

echo -e "${BLUE}步骤2: 优化TCP参数${NC}"
echo "======================================"

# 创建优化配置文件
cat > /etc/sysctl.d/99-webserver-optimization.conf << 'EOF'
# TinyWebServer 高性能优化配置
# 生成时间: $(date)

# ============================================
# TCP连接队列优化
# ============================================
# 增大全连接队列（accept队列）
net.core.somaxconn = 32768

# 增大半连接队列（SYN队列）
net.ipv4.tcp_max_syn_backlog = 32768

# ============================================
# 端口和连接优化
# ============================================
# 扩大客户端端口范围
net.ipv4.ip_local_port_range = 1024 65535

# 允许TIME_WAIT状态的socket重用
net.ipv4.tcp_tw_reuse = 1

# 减少FIN_WAIT2状态超时时间
net.ipv4.tcp_fin_timeout = 30

# 减少TIME_WAIT状态超时时间
net.ipv4.tcp_tw_timeout = 30

# ============================================
# 文件描述符优化
# ============================================
# 增加系统级文件描述符限制
fs.file-max = 1000000

# 增加inotify监控限制
fs.inotify.max_user_watches = 524288

# ============================================
# 网络缓冲区优化
# ============================================
# 增大网络接收缓冲区
net.core.rmem_max = 16777216
net.core.rmem_default = 262144

# 增大网络发送缓冲区
net.core.wmem_max = 16777216
net.core.wmem_default = 262144

# TCP读写缓冲区
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# 增大网络设备接收队列
net.core.netdev_max_backlog = 16384

# ============================================
# 连接跟踪优化
# ============================================
# 增加连接跟踪表大小
net.netfilter.nf_conntrack_max = 1000000
net.nf_conntrack_max = 1000000

# ============================================
# 其他TCP优化
# ============================================
# 启用TCP窗口缩放
net.ipv4.tcp_window_scaling = 1

# 启用时间戳
net.ipv4.tcp_timestamps = 1

# 启用选择性确认
net.ipv4.tcp_sack = 1

# TCP keepalive参数
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3

# ============================================
# 安全相关
# ============================================
# SYN Cookies保护（防SYN Flood攻击）
net.ipv4.tcp_syncookies = 1

# SYN-ACK重试次数
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 2
EOF

echo -e "${GREEN}✓ TCP参数配置已创建${NC}"
echo ""

echo -e "${BLUE}步骤3: 应用配置${NC}"
echo "======================================"
sysctl -p /etc/sysctl.d/99-webserver-optimization.conf

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ 系统参数优化成功${NC}"
else
    echo ""
    echo -e "${RED}✗ 部分参数应用失败，请检查系统是否支持${NC}"
fi
echo ""

echo -e "${BLUE}步骤4: 优化文件描述符限制${NC}"
echo "======================================"

# 备份limits.conf
cp /etc/security/limits.conf $BACKUP_DIR/

# 添加文件描述符限制
if ! grep -q "webserver nofile" /etc/security/limits.conf; then
    cat >> /etc/security/limits.conf << 'EOF'

# TinyWebServer 文件描述符优化
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
root soft nofile 65536
root hard nofile 65536
EOF
    echo -e "${GREEN}✓ 文件描述符限制已更新${NC}"
else
    echo -e "${YELLOW}⚠  文件描述符限制已存在，跳过${NC}"
fi
echo ""

echo -e "${BLUE}步骤5: 验证配置${NC}"
echo "======================================"
echo "当前重要参数值："
echo ""
echo "somaxconn: $(cat /proc/sys/net/core/somaxconn)"
echo "tcp_max_syn_backlog: $(cat /proc/sys/net/ipv4/tcp_max_syn_backlog)"
echo "ip_local_port_range: $(cat /proc/sys/net/ipv4/ip_local_port_range)"
echo "file-max: $(cat /proc/sys/fs/file-max)"
echo ""

# 检查当前会话的ulimit
echo "当前会话文件描述符限制: $(ulimit -n)"
echo -e "${YELLOW}注意: 新的文件描述符限制需要重新登录后生效${NC}"
echo ""

echo -e "${BLUE}步骤6: 禁用不必要的服务（可选）${NC}"
echo "======================================"
read -p "是否禁用防火墙以提升性能？(y/n) [n]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # UFW (Ubuntu/Debian)
    if command -v ufw &> /dev/null; then
        ufw disable
        echo -e "${GREEN}✓ UFW防火墙已禁用${NC}"
    fi
    
    # Firewalld (CentOS/RHEL)
    if command -v firewall-cmd &> /dev/null; then
        systemctl stop firewalld
        systemctl disable firewalld
        echo -e "${GREEN}✓ Firewalld已禁用${NC}"
    fi
    
    echo -e "${YELLOW}⚠  生产环境请谨慎禁用防火墙！${NC}"
else
    echo "保持防火墙启用"
fi
echo ""

echo "======================================"
echo -e "${GREEN}✓ 系统优化完成！${NC}"
echo "======================================"
echo ""
echo "优化内容："
echo "  ✓ TCP连接队列增大到32768"
echo "  ✓ 端口范围扩展到1024-65535"
echo "  ✓ 文件描述符限制提升到65536"
echo "  ✓ 网络缓冲区优化"
echo "  ✓ 连接跟踪表扩大"
echo ""
echo -e "${YELLOW}重要提示：${NC}"
echo "  1. 文件描述符限制需要 ${RED}重新登录${NC} 后生效"
echo "  2. 其他参数已立即生效"
echo "  3. 配置备份在: $BACKUP_DIR"
echo "  4. 如需恢复，请联系系统管理员"
echo ""
echo "下一步："
echo "  1. 重新登录（或运行: exec su -l \$USER）"
echo "  2. 验证: ulimit -n (应该显示 65536)"
echo "  3. 编译服务器: make clean && make"
echo "  4. 开始测试: ./物理机压测脚本.sh"
echo ""

