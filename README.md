# 安路FPGA多媒体信息发布终端：工程代码

面向园区数字标牌与应急信息发布场景的 FPGA 多媒体信息终端工程。基于安路 EG4S20BG256，无CPU、无操作系统，全部逻辑在 FPGA 内实现。

## 工程入口

- TD 工程：`src/td_project/HDMI1.4b_Transmitter_v1.0.al`（工具 Tang Dynasty 6.2.168116，器件 EG4S20BG256）
- 顶层模块：`top`（源文件 `src/user_source/hdl_source/top_tf_hdmi_audio.v`）
- 引脚/时序约束：`src/user_source/constraints_source/pin.adc`、`timing.sdc`

## 目录说明

- `src/`：全部 RTL 源码、官方 IP 与生成代码、音频/OSD ROM 数据、约束与 TD 工程（128 个文件）
- `verification/`：测试台与 16 项通过日志（快速启动管线、场景控制、CDC 握手、OSD、音频链路、存储带宽负载等），`result_manifest.csv` 为结果清单
- `tf_pages/`：TF 卡四张 BMP 底图（P1 启动页、P2 园区通知、P3 活动宣传、P4 应急信息；640×480、24 位，各 921654 字节）
- `tools/`：OSD/音频 ROM 与素材生成脚本
- `release/`：最终布线时序与资源报告（`final_timing.rpt`、`resource.area`）
- `fpga_boot_audio_delay_20261025.bit`：已验收固件，706448 字节，SHA256 `7BF9CA8600A75FE9347A23799B4C13C788037AE5552F97A014A7B4292E493316`

## 上电运行

1. TF 卡格式化 FAT32，拷入 `tf_pages/` 四张 BMP，插入板载卡槽
2. HDMI 连接带扬声器显示器
3. 上电：P1 启动页完整显示约 3 秒（约 1 秒时播放启动提示音），随后自动进入 P2/P3 日常轮播（每页完整显示约 8 秒）

按键定义（按板面丝印）：KEY1 复位；KEY2 应急进入/解除（帧边界直切+场景音）；KEY3 五档亮度循环（OSD 弹窗反馈）；KEY4 日常轮播暂停/恢复。RTL 端口编号与板面丝印不一致，操作以丝印为准。

## 资源与时序

LUT 6138/19600（31.32%），寄存器 4108/19600（20.96%），9K BRAM 26/64（40.62%），32K BRAM 15/16（93.75%），DSP 8/29（27.59%），PLL 3/4（75.00%）。
最终布线：Setup WNS +0.101 ns、Hold WNS +0.011 ns，Setup/Hold TNS 均为 0 ns。

## 重建说明

TD 打开 `.al` 工程后依次执行综合与布局布线即可。重新构建得到的布局与交付固件可能不同，上板前应重新进行功能验证；本目录交付的固件代表已验收版本。
`SHA256SUMS.csv` 为本目录全部文件的 SHA256 散列清单。
