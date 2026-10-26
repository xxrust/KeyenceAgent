# windows-ui-automation

通用 Windows 桌面 UI 自动化与调试 skill。跨应用：方法、决策树、症状表、基础函数。

## 安装（本机已建立 junction）

```powershell
New-Item -ItemType Junction `
  -Path   "$env:USERPROFILE\.dsh\skills\windows-ui-automation" `
  -Target "H:\KeyenceAgent\windows-ui-automation"
```

junction 建立后，下次会话的 skill 目录会列出 `windows-ui-automation`。

## 结构

```
windows-ui-automation/
├─ SKILL.md                      # 入口：铁律、流程、选型、症状表
├─ references/
│  ├─ win32-cheatsheet.md        # 枚举、消息、焦点、坐标、原子手势
│  ├─ uia-cheatsheet.md          # Pattern、阻塞、自绘控件替代
│  ├─ failure-playbook.md        # 按症状排查
│  └─ case-studies.md            # KV STUDIO 真实案例与证据
└─ scripts/
   ├─ UiProbe.ps1                # 通用探测/点击/截图/弹窗函数
   └─ Test-UiProbe.ps1           # 自检（23 项，需真实桌面会话）
```

## 自检

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-UiProbe.ps1 -OutDir C:\kvrun\uiprobe
```

期望：`exit 0`，`test_result.json` 里 `failed=0`。自检会枚举当前可见窗口、读子控件、截图，不点击任何业务窗口。

## 与 KEYENCE skill 的边界

| Skill | 负责 |
| --- | --- |
| `windows-ui-automation`（本 skill） | 通用方法、跨应用坑、基础函数 |
| `kv-studio-operator` | KV STUDIO 脚本入口、workflow、验证矩阵 |
| `kv-ui-screenshot-verification` | KV 界面“截图优先”纪律与项目内踩坑清单 |

新增 KV 专属坑 → 写进 `kv-ui-screenshot-verification`；可复用的方法 → 写进本 skill。
