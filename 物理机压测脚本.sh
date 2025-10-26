#!/bin/bash

# TinyWebServer 物理机压测脚本（通用版）
# 自动检测项目路径，无硬编码

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取脚本所在目录（项目根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

echo "======================================"
echo "TinyWebServer 物理机压力测试"
echo "======================================"
echo "项目路径: $PROJECT_ROOT"
echo ""

# ============================================
# 步骤1: 系统环境检查
# ============================================
echo -e "${BLUE}步骤1: 检查系统环境${NC}"
echo "======================================"

# 检查操作系统
OS_INFO=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | cut -d'"' -f2)
KERNEL=$(uname -r)
CPU_CORES=$(nproc)
TOTAL_MEM=$(free -h | grep Mem | awk '{print $2}')

echo "操作系统: $OS_INFO"
echo "内核版本: $KERNEL"
echo "CPU核心数: $CPU_CORES"
echo "总内存: $TOTAL_MEM"
echo ""

# 检查文件描述符限制
FD_LIMIT=$(ulimit -n)
echo "文件描述符限制: $FD_LIMIT"
if [ $FD_LIMIT -lt 65536 ]; then
    echo -e "${RED}❌ 警告: 文件描述符限制太小！${NC}"
    echo "当前: $FD_LIMIT, 建议: 65536"
    echo ""
    echo "临时解决方案: ulimit -n 65536"
    echo "永久解决方案: sudo ./物理机系统优化.sh"
    echo ""
    read -p "是否继续？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo -e "${GREEN}✓ 文件描述符限制充足${NC}"
fi
echo ""

# 检查TCP参数
SOMAXCONN=$(cat /proc/sys/net/core/somaxconn)
SYN_BACKLOG=$(cat /proc/sys/net/ipv4/tcp_max_syn_backlog)
PORT_RANGE=$(cat /proc/sys/net/ipv4/ip_local_port_range)

echo "TCP参数："
echo "  somaxconn: $SOMAXCONN"
echo "  tcp_max_syn_backlog: $SYN_BACKLOG"
echo "  ip_local_port_range: $PORT_RANGE"
echo ""

NEED_OPTIMIZE=0
if [ $SOMAXCONN -lt 16384 ] || [ $SYN_BACKLOG -lt 16384 ]; then
    echo -e "${YELLOW}⚠️  建议运行系统优化脚本: sudo ./物理机系统优化.sh${NC}"
    NEED_OPTIMIZE=1
fi

if [ $NEED_OPTIMIZE -eq 1 ]; then
    read -p "是否继续测试？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi
echo ""

# ============================================
# 步骤2: 编译检查
# ============================================
echo -e "${BLUE}步骤2: 检查编译状态${NC}"
echo "======================================"

cd "$PROJECT_ROOT"

if [ ! -f "server" ]; then
    echo -e "${YELLOW}⚠️  未找到 server 可执行文件${NC}"
    read -p "是否现在编译？(y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "开始编译..."
        make clean
        make
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ 编译失败！${NC}"
            exit 1
        fi
        echo -e "${GREEN}✓ 编译成功${NC}"
    else
        echo "请先编译: make"
        exit 1
    fi
else
    echo -e "${GREEN}✓ 找到 server 可执行文件${NC}"
    
    # 检查是否需要重新编译
    read -p "是否重新编译以确保代码最新？(y/n) [n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        make clean && make
        echo -e "${GREEN}✓ 重新编译完成${NC}"
    fi
fi
echo ""

# 检查WebBench
echo "检查WebBench..."
if [ ! -f "test_pressure/webbench-1.5/webbench" ]; then
    echo -e "${YELLOW}⚠️  WebBench未编译${NC}"
    cd test_pressure/webbench-1.5
    make clean && make
    cd "$PROJECT_ROOT"
    echo -e "${GREEN}✓ WebBench编译完成${NC}"
else
    echo -e "${GREEN}✓ WebBench已准备就绪${NC}"
fi
echo ""

# ============================================
# 步骤3: 清理旧进程
# ============================================
echo -e "${BLUE}步骤3: 清理旧进程${NC}"
echo "======================================"
pkill -9 server 2>/dev/null
sleep 2
echo -e "${GREEN}✓ 已清理${NC}"
echo ""

# ============================================
# 步骤4: 配置测试参数
# ============================================
echo -e "${BLUE}步骤4: 配置测试参数${NC}"
echo "======================================"

# 推荐线程数
RECOMMENDED_THREADS=$((CPU_CORES * 2))

echo "检测到 $CPU_CORES 个CPU核心"
echo "推荐线程数: $RECOMMENDED_THREADS"
echo ""

echo "请选择测试方案："
echo "  1) 快速验证测试 (1000并发, 10秒)"
echo "  2) 基准性能测试 (3000并发, 30秒)"
echo "  3) 高负载测试   (5000并发, 30秒)"
echo "  4) 极限性能测试 (10000并发, 30秒)"
echo "  5) 超限冲击测试 (10500并发, 5秒)"
echo "  6) 完整测试套件 (全部执行)"
echo "  7) 自定义测试"
echo ""
read -p "请选择 [1-7]: " TEST_CHOICE

case $TEST_CHOICE in
    1)
        CONCURRENCY=1000
        DURATION=10
        THREADS=$RECOMMENDED_THREADS
        ;;
    2)
        CONCURRENCY=3000
        DURATION=30
        THREADS=$RECOMMENDED_THREADS
        ;;
    3)
        CONCURRENCY=5000
        DURATION=30
        THREADS=$(($RECOMMENDED_THREADS + 16))
        ;;
    4)
        CONCURRENCY=10000
        DURATION=30
        THREADS=$(($RECOMMENDED_THREADS + 32))
        ;;
    5)
        CONCURRENCY=10500
        DURATION=5
        THREADS=$(($RECOMMENDED_THREADS + 32))
        ;;
    6)
        # 完整测试套件
        echo ""
        echo -e "${GREEN}将执行完整测试套件${NC}"
        ;;
    7)
        echo ""
        read -p "并发数: " CONCURRENCY
        read -p "持续时间(秒): " DURATION
        read -p "线程数 [$RECOMMENDED_THREADS]: " THREADS
        THREADS=${THREADS:-$RECOMMENDED_THREADS}
        ;;
    *)
        echo "无效选择，使用默认配置"
        CONCURRENCY=3000
        DURATION=30
        THREADS=$RECOMMENDED_THREADS
        ;;
esac

# ============================================
# 执行测试函数
# ============================================
run_single_test() {
    local concurrency=$1
    local duration=$2
    local threads=$3
    local mode=$4
    local mode_name=$5
    
    echo ""
    echo "======================================"
    echo "测试配置: $mode_name"
    echo "======================================"
    echo "并发数: $concurrency"
    echo "持续时间: ${duration}秒"
    echo "线程数: $threads"
    echo "触发模式: $mode_name"
    echo ""
    
    # 启动服务器
    echo "启动服务器..."
    cd "$PROJECT_ROOT"
    ./server -c 1 -m $mode -a 0 -s 32 -t $threads > /dev/null 2>&1 &
    SERVER_PID=$!
    echo "服务器PID: $SERVER_PID"
    
    # 等待服务器启动
    sleep 3
    
    # 检查服务器是否运行
    if ! ps -p $SERVER_PID > /dev/null; then
        echo -e "${RED}❌ 服务器启动失败！${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 服务器启动成功${NC}"
    echo ""
    
    # 执行压测
    echo "开始压力测试..."
    echo "======================================"
    cd "$PROJECT_ROOT/test_pressure/webbench-1.5"
    ./webbench -c $concurrency -t $duration http://127.0.0.1:9006/judge.html
    
    WEBBENCH_EXIT=$?
    
    # 查看服务器状态
    echo ""
    echo "服务器状态："
    echo "======================================"
    if ps -p $SERVER_PID > /dev/null; then
        echo -e "${GREEN}✓ 服务器仍在运行${NC}"
        echo ""
        ps -p $SERVER_PID -o pid,vsz,rss,%cpu,%mem,cmd
        echo ""
        echo "TCP连接统计:"
        ss -s | grep -E "TCP:|estab" || netstat -s | grep -i tcp | head -5
    else
        echo -e "${RED}❌ 服务器已崩溃！${NC}"
    fi
    
    # 停止服务器
    echo ""
    kill $SERVER_PID 2>/dev/null
    sleep 2
    pkill -9 server 2>/dev/null
    
    cd "$PROJECT_ROOT"
    
    return $WEBBENCH_EXIT
}

# ============================================
# 步骤5: 执行测试
# ============================================
echo ""
echo -e "${BLUE}步骤5: 开始压力测试${NC}"

if [ "$TEST_CHOICE" == "6" ]; then
    # 完整测试套件
    echo "======================================"
    echo "执行完整测试套件"
    echo "======================================"
    
    # 创建结果文件
    RESULT_FILE="test_results_$(date +%Y%m%d_%H%M%S).txt"
    
    echo "TinyWebServer 压力测试报告" > $RESULT_FILE
    echo "测试时间: $(date)" >> $RESULT_FILE
    echo "系统信息: $OS_INFO" >> $RESULT_FILE
    echo "CPU核心: $CPU_CORES, 内存: $TOTAL_MEM" >> $RESULT_FILE
    echo "======================================" >> $RESULT_FILE
    echo "" >> $RESULT_FILE
    
    # 测试1
    echo "【测试1/5】快速验证 - 1000并发" | tee -a $RESULT_FILE
    run_single_test 1000 10 $RECOMMENDED_THREADS 1 "Proactor-LT+ET" | tee -a $RESULT_FILE
    sleep 5
    
    # 测试2
    echo "【测试2/5】基准测试 - 3000并发" | tee -a $RESULT_FILE
    run_single_test 3000 30 $RECOMMENDED_THREADS 1 "Proactor-LT+ET" | tee -a $RESULT_FILE
    sleep 5
    
    # 测试3
    echo "【测试3/5】高负载 - 5000并发" | tee -a $RESULT_FILE
    run_single_test 5000 30 $(($RECOMMENDED_THREADS + 16)) 1 "Proactor-LT+ET" | tee -a $RESULT_FILE
    sleep 5
    
    # 测试4
    echo "【测试4/5】极限测试 - 10000并发" | tee -a $RESULT_FILE
    run_single_test 10000 30 $(($RECOMMENDED_THREADS + 32)) 1 "Proactor-LT+ET" | tee -a $RESULT_FILE
    sleep 5
    
    # 测试5
    echo "【测试5/5】超限冲击 - 10500并发" | tee -a $RESULT_FILE
    run_single_test 10500 5 $(($RECOMMENDED_THREADS + 32)) 1 "Proactor-LT+ET" | tee -a $RESULT_FILE
    
    echo ""
    echo "======================================"
    echo -e "${GREEN}✓ 完整测试套件执行完毕${NC}"
    echo "======================================"
    echo "测试结果已保存到: $RESULT_FILE"
    
else
    # 单次测试
    run_single_test $CONCURRENCY $DURATION $THREADS 1 "Proactor-LT+ET"
fi

echo ""
echo "======================================"
echo -e "${GREEN}压测完成！${NC}"
echo "======================================"
echo ""
echo "建议下一步："
echo "  1. 查看测试结果，记录QPS和成功率"
echo "  2. 尝试不同的触发模式 (-m 0/1/2/3)"
echo "  3. 调整线程数，找到最佳配置"
echo "  4. 使用监控脚本观察资源使用"
echo ""

