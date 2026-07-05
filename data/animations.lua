local animations = {
    healing_sparkle = {
        type = "text_flow_liquid",
        sequence = "⋆｡°✩",
        duration = 1000,
        interval = 50,
        color = {170/255, 255/255, 170/255}, -- Light green
        targetPart = "hp_gauge"
    },
    damage_shake = {
        type = "shake",
        duration = 500
    },
    attack_flash = {
        type = "flash",
        duration = 200,
        color = {1, 1, 1}
    },
    death = {
        type = "death_sequence",
        duration = 1000
    }
}

return animations
