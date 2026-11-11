-- 全人物天赋点亮（客户端本地模组）
-- 只改账号侧 Insight / 亲和 KV，不改世界逻辑，尽量避开 Combined Status、
-- Geometric Placement、Minimap HUD 等热门 HUD/建造模组的冲突面。

name = "全人物天赋点亮"
description = [[本地客户端模组：为所有已有技能树的人物拉满洞察（Insight）点数，并解锁影/月亲和等常见前置条件。

· 进度写在你的账号侧，进入别人的存档/公共服也能带着用
· 不改 TUNING、不 Hook HUD/组件，尽量不与订阅量最高的热门模组冲突
· 默认「满点 + 解锁锁」，由你在技能树界面自行点亮节点；可选一键尝试激活全部节点（影/月互斥时可能异常，慎用）

使用：启用后进主菜单稍等片刻，或打开控制台（~）本地执行：UnlockAllSkills()]]
author = "Silver Wolf"
version = "1.0.0"
forumthread = ""

api_version = 10
priority = -10

dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false
shipwrecked_compatible = false
hamlet_compatible = false

client_only_mod = true
all_clients_require_mod = false

configuration_options =
{
    {
        name = "auto_unlock",
        label = "启动时自动拉满",
        hover = "进入主菜单后自动拉满洞察并解锁亲和前置",
        options =
        {
            {description = "开启", data = true},
            {description = "关闭（仅手动）", data = false},
        },
        default = true,
    },
    {
        name = "activate_all_nodes",
        label = "尝试点亮全部节点",
        hover = "在满点之外强制激活树上每个技能。影/月互斥可能导致异常，默认关闭",
        options =
        {
            {description = "关闭（推荐）", data = false},
            {description = "开启", data = true},
        },
        default = false,
    },
    {
        name = "announce",
        label = "完成后提示",
        hover = "在主菜单打印一条完成提示",
        options =
        {
            {description = "开启", data = true},
            {description = "关闭", data = false},
        },
        default = true,
    },
}
