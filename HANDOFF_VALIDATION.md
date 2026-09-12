# R005/r1 验证摘要

- 被验证源码：`c81d1c53487c2468dd2175e1491b7194026ee1c7`。
- Opus执行：Icarus 12.0下 parser、block builder、BRAM pingpong、four-channel aligner、CH0 aligner、CH0 controller六项编译/执行退出0。
- Vivado 2025.2：短路径隔离构建退出0；part `xc7z020clg400-2`，top `ch0_test_top`，WNS 8.792 ns，DRC errors 0。首次长路径失败日志保留。
- bit：4045688 bytes，SHA-256 `2fc4538dce9b1620f8eb75d54cbeda946612b0b0971504ff0a85e714592fb139`。
- LTX：159677 bytes，SHA-256 `5f76959bbb0d54d3d9c6b37dfb089395d62192d518b75bd71f1dd1fe0b1e3000`。
- 未验证：完整board_top四路/FMC实现、烧录、ILA、板测、r8恢复候选。

Astra核验交付清单及基线，未重新运行Vivado。原始日志保留在本地工作区 `artifacts/collaboration/R005/r1/opus/logs/zynq_*`，不是本仓附件；独立开发时按HANDOFF重建。此源码交接不附带获准烧录镜像。
