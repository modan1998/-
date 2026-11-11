name = "鱼人永久忠诚（主机）"
description = [[服务端模组：鱼人妹（或配置为任意玩家）雇佣的鱼人/守卫：
· 忠诚永不超时
· 玩家死亡/变鬼/复活后仍保持跟随
· 进出洞穴（跨世界）会一起迁移，地洞内仍永久忠诚，回地面一起回来
· 普通鱼人喂食两次月亮碎片可变成守卫鱼人：第一次按技能树正常升级（需点亮月亮亲和「月石变异鱼人」）；第二次需存在鱼人王与鱼人堡垒，且目标鱼人须在鱼人王10个地皮（40单位）范围内。升级后保留原版守卫全部功能，并永久忠诚

注意：仅在启用本模组的存档/服务器上生效。不会上传创意工坊。]]
author = "Silver Wolf"
version = "1.3.0"
forumthread = ""

api_version = 10
priority = 10

dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false

client_only_mod = false
all_clients_require_mod = false

server_filter_tags = {"wurt", "merm", "tweak"}

configuration_options =
{
    {
        name = "only_wurt",
        label = "仅鱼人妹领袖",
        hover = "开启后只有领袖为 Wurt 时才永久忠诚；关闭则任意玩家雇佣的鱼人也永久",
        options =
        {
            {description = "仅 Wurt", data = true},
            {description = "任意玩家", data = false},
        },
        default = true,
    },
    {
        name = "include_guards",
        label = "包含鱼人守卫",
        options =
        {
            {description = "是", data = true},
            {description = "否", data = false},
        },
        default = true,
    },
}
