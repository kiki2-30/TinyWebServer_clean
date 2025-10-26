#!/bin/bash
# TinyWebServer 压力测试脚本

echo "================================================"
echo "TinyWebServer 压力测试脚本"
echo "================================================"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查服务器是否运行
check_server() {
    if ! nc -z 127.0.0.1 9006 2>/dev/null; then
        echo -e "${RED}错误：服务器未在端口9006上运行！${NC}"
        echo "请先启动服务器："
        echo "  cd /home/kiki/TinyWebServer_clean"
        echo "  ./server -c 1 -m 0 -a 0 -t 32"
        exit 1
    fi
    echo -e "${GREEN}✓ 检测到服务器正在运行${NC}"
    echo ""
}

# 运行压测
run_benchmark() {
    local clients=$1
    local time=$2
    local desc=$3
    
    echo -e "${YELLOW}测试配置：${desc}${NC}"
    echo "并发客户端数：${clients}"
    echo "测试时间：${time}秒"
    echo "开始测试..."
    echo "----------------------------------------"
    
    # 临时禁用代理（避免通过代理连接localhost）
    unset http_proxy
    unset https_proxy
    unset HTTP_PROXY
    unset HTTPS_PROXY
    
    cd /home/kiki/TinyWebServer_clean/test_pressure/webbench-1.5
    ./webbench -c ${clients} -t ${time} http://127.0.0.1:9006/
    
    echo "----------------------------------------"
    echo ""
}

# 主菜单
show_menu() {
    echo "请选择测试类型："
    echo "1) 轻量测试 (100客户端, 10秒)"
    echo "2) 中等测试 (500客户端, 30秒)"
    echo "3) 重度测试 (1000客户端, 30秒)"
    echo "4) 极限测试 (10500客户端, 5秒)"
    echo "5) 自定义测试"
    echo "6) 退出"
    echo ""
    read -p "请输入选项 [1-6]: " choice
    
    case $choice in
        1)
            run_benchmark 100 10 "轻量测试"
            ;;
        2)
            run_benchmark 500 30 "中等测试"
            ;;
        3)
            run_benchmark 1000 30 "重度测试"
            ;;
        4)
            run_benchmark 10500 5 "极限测试"
            ;;
        5)
            read -p "请输入并发客户端数: " clients
            read -p "请输入测试时间(秒): " time
            run_benchmark ${clients} ${time} "自定义测试"
            ;;
        6)
            echo "退出测试"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项！${NC}"
            echo ""
            show_menu
            ;;
    esac
    
    # 询问是否继续测试
    echo ""
    read -p "是否继续测试？[y/n]: " continue
    if [ "$continue" = "y" ] || [ "$continue" = "Y" ]; then
        echo ""
        show_menu
    fi
}

# 主程序
main() {
    check_server
    show_menu
}

main

