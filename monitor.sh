#!/bin/bash

# TinyWebServer 实时性能监控脚本

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 查找服务器进程
SERVER_PID=$(pgrep -f "^\./server" | head -1)

if [ -z "$SERVER_PID" ]; then
    echo "未找到运行中的服务器进程"
    echo "请先启动服务器: ./server"
    exit 1
fi

echo "监控服务器进程: $SERVER_PID"
echo "按 Ctrl+C 退出监控"
echo ""
sleep 2

while true; do
    clear
    
    echo "======================================"
    echo "TinyWebServer 实时监控"
    echo "======================================"
    date
    echo ""
    
    # 检查进程是否还在运行
    if ! ps -p $SERVER_PID > /dev/null 2>&1; then
        echo -e "${RED}❌ 服务器进程已退出！${NC}"
        break
    fi
    
    # ============================================
    # 进程信息
    # ============================================
    echo -e "${BLUE}【进程信息】${NC}"
    ps -p $SERVER_PID -o pid,ppid,user,%cpu,%mem,vsz,rss,stat,start,time,cmd --no-headers | \
    awk '{printf "PID: %s | CPU: %s%% | 内存: %s%% | VSZ: %s KB | RSS: %s KB\n启动时间: %s | 运行时长: %s\n状态: %s | 命令: %s\n", 
          $1, $4, $5, $6, $7, $9, $10, $8, substr($0, index($0,$11))}'
    echo ""
    
    # ============================================
    # CPU详细信息
    # ============================================
    echo -e "${BLUE}【CPU使用率（各核心）】${NC}"
    top -b -n 1 -p $SERVER_PID | grep "Cpu" | head -4
    echo ""
    
    # ============================================
    # 内存详细信息
    # ============================================
    echo -e "${BLUE}【内存使用】${NC}"
    free -h | awk 'NR==1{print $1"\t"$2"\t\t"$3"\t\t"$4"\t\t"$7} NR==2{print $1"\t"$2"\t"$3"\t"$4"\t"$7}'
    echo ""
    
    RSS_MB=$(ps -p $SERVER_PID -o rss= | awk '{printf "%.2f", $1/1024}')
    VSZ_MB=$(ps -p $SERVER_PID -o vsz= | awk '{printf "%.2f", $1/1024}')
    echo "服务器内存: RSS=${RSS_MB}MB, VSZ=${VSZ_MB}MB"
    echo ""
    
    # ============================================
    # TCP连接统计
    # ============================================
    echo -e "${BLUE}【TCP连接统计】${NC}"
    
    # 使用ss（更快）或netstat
    if command -v ss &> /dev/null; then
        ss -s | grep -E "TCP:"
        echo ""
        
        # 连接状态分布
        echo "连接状态分布:"
        ss -tan | awk 'NR>1 {state[$1]++} END {for(s in state) printf "  %-15s: %d\n", s, state[s]}' | sort -k2 -rn
    else
        netstat -s | grep -i tcp | head -5
        echo ""
        
        echo "连接状态分布:"
        netstat -an | awk '/^tcp/ {state[$NF]++} END {for(s in state) printf "  %-15s: %d\n", s, state[s]}' | sort -k2 -rn
    fi
    echo ""
    
    # 服务器监听端口的连接数
    SERVER_PORT=$(lsof -p $SERVER_PID -a -i TCP -s TCP:LISTEN 2>/dev/null | awk 'NR>1 {split($9,a,":"); print a[2]}' | head -1)
    if [ ! -z "$SERVER_PORT" ]; then
        CONN_COUNT=$(ss -tan "sport = :$SERVER_PORT" 2>/dev/null | wc -l)
        echo "端口 $SERVER_PORT 的连接数: $((CONN_COUNT - 1))"
    fi
    echo ""
    
    # ============================================
    # 网络流量
    # ============================================
    echo -e "${BLUE}【网络流量】${NC}"
    
    # 获取网络接口流量
    NETWORK_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ ! -z "$NETWORK_INTERFACE" ]; then
        RX_BYTES=$(cat /sys/class/net/$NETWORK_INTERFACE/statistics/rx_bytes 2>/dev/null)
        TX_BYTES=$(cat /sys/class/net/$NETWORK_INTERFACE/statistics/tx_bytes 2>/dev/null)
        
        if [ ! -z "$RX_BYTES" ] && [ ! -z "$TX_BYTES" ]; then
            RX_MB=$(echo "scale=2; $RX_BYTES / 1024 / 1024" | bc)
            TX_MB=$(echo "scale=2; $TX_BYTES / 1024 / 1024" | bc)
            echo "网卡 $NETWORK_INTERFACE:"
            echo "  接收: ${RX_MB} MB"
            echo "  发送: ${TX_MB} MB"
        fi
    fi
    echo ""
    
    # ============================================
    # 文件描述符使用
    # ============================================
    echo -e "${BLUE}【文件描述符】${NC}"
    FD_COUNT=$(ls /proc/$SERVER_PID/fd 2>/dev/null | wc -l)
    FD_LIMIT=$(cat /proc/$SERVER_PID/limits 2>/dev/null | grep "open files" | awk '{print $4}')
    echo "当前使用: $FD_COUNT"
    echo "软限制: $FD_LIMIT"
    
    if [ ! -z "$FD_LIMIT" ] && [ "$FD_LIMIT" != "unlimited" ]; then
        FD_PERCENT=$(echo "scale=2; $FD_COUNT * 100 / $FD_LIMIT" | bc)
        echo "使用率: ${FD_PERCENT}%"
        
        if (( $(echo "$FD_PERCENT > 80" | bc -l) )); then
            echo -e "${YELLOW}⚠️  文件描述符使用率过高！${NC}"
        fi
    fi
    echo ""
    
    # ============================================
    # 系统负载
    # ============================================
    echo -e "${BLUE}【系统负载】${NC}"
    uptime
    echo ""
    
    # ============================================
    # 磁盘IO（如果开启了日志）
    # ============================================
    echo -e "${BLUE}【磁盘IO】${NC}"
    if command -v iostat &> /dev/null; then
        iostat -x 1 1 | awk '/^Device:|^[a-z]/ && !/loop/ {print}'
    else
        echo "未安装 iostat (可选: apt install sysstat)"
    fi
    echo ""
    
    # ============================================
    # 线程信息
    # ============================================
    echo -e "${BLUE}【线程信息】${NC}"
    THREAD_COUNT=$(ps -p $SERVER_PID -T | wc -l)
    echo "线程数: $((THREAD_COUNT - 1))"
    echo ""
    
    # 刷新间隔
    echo "======================================"
    echo "下次刷新: 2秒后"
    echo "======================================"
    
    sleep 2
done

echo ""
echo "监控已退出"

