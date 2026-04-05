import '../models/ingredient.dart';
import '../models/shopping_item.dart';
import '../models/storage_area.dart';

class MockData {
  static const profileImageUrl =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuA8SCM01oa7CpbTrDgeAHWZj7h69juIfuYNsE15eEtD7eRxzdUEoCvBUg4mE086bG67lLyegNYz2LCDpPXY9pbr_DyHHbyNjmErpw2z0FqirVe6VlGmqF3eJxrOuMn4wXkrziJH7ekSzyX5PGL1vdzEwNVhB4syDWMqx9YSg9CTxBIDEZDhKR5c1fWo3OC9FTTZHzM0a-L2uE9AQApwgdWrT-NHkxNHNKGgE68zlWw61XHXzeBob_jq6vlnSusJiaZbnD5LHsVWt4gc';

  static const inventoryItems = [
    Ingredient(
      name: '传家宝番茄',
      quantity: '4 个',
      unit: '800g',
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuBkHXey93L_I_n3faNS8lgI3xWvlEqcnph4IcFajOgeQKACr6yovg8X66Fh9jq218RxHEGB93AkkC0G_dNavJs2_LmprUzLGyDkyrFBfuiuSUqCwVGhuc4ApYWWVRou2zNTbWgGfqcLNTER25ZxGMiy5vkR8SjrADrnjfRXSTiLEwBRg4ZLAqgMIqYnhJnjbm6gy_y5yBSG7xbRtKaH7tI6xK3J-y9_aVRBX_BdMGBYDFFDbuBfDhKzSgL6GM0lKh3DV-57yQrqFoh9',
      freshnessPercent: 0.85,
      state: FreshnessState.fresh,
      expiryLabel: '新鲜',
      category: '蔬菜',
    ),
    Ingredient(
      name: '有机全脂牛奶',
      quantity: '1 瓶',
      unit: '1L',
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuDn8fN37G-MfYbCckPLcFSDK6yXAS-voxXPAaxzxMVPICdfQnJkeKhj4JYgWhPaz-WuLTeZILBicj7bOGCFUAGOqYtU8XUXqh49j6FPEbMZa92KoX4KxeChg4U6TGemOUVCor1KwoJFyV27aIm90BIV5KxryEdil4U1x41nyaY8jJQ376bqfurGmBVtpwKO0yfx7x_Z56ig6vn7XF07NOCQXbR0aVqrggJ28vcDdsBn7rFYUYU8ZiHqy-VSxZ11qLzM9YT1FK0RXRyU',
      freshnessPercent: 0.30,
      state: FreshnessState.expiringSoon,
      expiryLabel: '2天后过期',
      category: '乳制品',
    ),
    Ingredient(
      name: '嫩菠菜',
      quantity: '1 袋',
      unit: '250g',
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuBGUDpnG0zjqYhH4aVck4qfTMe7X0gZkRsGdAYKgi6TRGahzf6KDdZGrnVR_xT6qx0wJkoT4KPUeZuO4sWyCJKw5A6XVPI6iiyJNKGJtkPll5YdiEDIexfNDoaFa3-pjdMGoLMJSNfjSlcZ9HYDeo2FcR2SgQMSuveea27MgfpDhg_RY3J9ecS3YyDZrWzKTsGti-5hOi-QuD-TnadvCPueC0E7jYItDZixdwyduhOBv3zwCLmhH2_yPXt8kGEdR-551Ek3z0MNt5cq',
      freshnessPercent: 0.05,
      state: FreshnessState.expired,
      expiryLabel: '昨日已过期',
      category: '蔬菜',
    ),
    Ingredient(
      name: '散养鸡蛋',
      quantity: '12 个',
      unit: 'A级',
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuBltA5cSMAcrrekoQLcmU4ABkhNTCLXaY3VPjJOgW6k20Q2WnlPzNK35E_saQQriTHHEAS3BbrBP3i8ddBpV9BoA6iiUe730_ld-XAgQOFU2sHva7QGLlUGH6QYSok1Zibv1MraEns-Pg53aOQQUCEZjUcM6l9Y6HADFdSxZw9SgO53BrSC-iYTEf5dzhmHbZRjKD9kTVWWvSrBxzrkE6LaPX7voWC2V8LkXZGfpQeRQ44Ai5PEVgD_6FQfy8x9WN9bDOexPYcBR7mn',
      freshnessPercent: 0.95,
      state: FreshnessState.fresh,
      expiryLabel: '新鲜',
      category: '蛋白质',
    ),
    Ingredient(
      name: '手工法棍',
      quantity: '1 条',
      unit: '新鲜烘焙',
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuAyfWkqXSAjVvvAU4I-q6Xjr8cH-_DPRqVeOmbDidXAKEM64bqLBanYA1sNgP-b4s80zMPRgQhk4ScSf-fxdHOJ_8FxhQ5OXlCRs3j2W1VG5jaYTZp8vCxkPGRaPtiI_9aLZDe0gGemtAjhcuDlx5f3CJOmeq6xOutfr09NlWpR9owIFg4ObwMCV7LCnxrGjHjMDyuvuAnSmdNjdOeV0LXe5rYxLsSKx8nGA3pVRm3C_HiG9L8KTut33wRgMTkKkXBDhTQYAQGmjsb7',
      freshnessPercent: 0.45,
      state: FreshnessState.expiringSoon,
      expiryLabel: '明天前食用',
      category: '谷物',
    ),
    Ingredient(
      name: '肋眼牛排',
      quantity: '2 块',
      unit: '600g',
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuC47HEYafENhkzbOy7bLX2wYyFLvIYsZmMbOFHUGFa5Ws_uP9mZBpMKRnTpVAk9y-kfQt52h9ibzhuQo0rdU70lxhImMZevHhuLW18gUXQG89YzIPC1mw1deRlQ-a_wCULGBTnBGNMLST2LXuDv2hoDObSb9lvWquJx2wQfAjELZ0_PHx3cRFo0p_FwUO4KVl3X1r10r5MP0DKnIlPTvEz81ejBYGIrMbwXSTB0hiKJCMuUxPL_ncw86Dxe4l0-PMaUGtp7y7OVPCYc',
      freshnessPercent: 0.70,
      state: FreshnessState.fresh,
      expiryLabel: '新鲜',
      category: '蛋白质',
    ),
  ];

  static const recentAdditions = [
    Ingredient(
      name: '传家宝胡萝卜',
      quantity: '500g',
      unit: '2小时前添加',
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuDafNvr8G4rKl9QmPTn0dqa5Oaiyb1zB-HNgEoV6BS9gtu6PEmQ-rKVu_Rsd32O3c-mN1Iea-WP8qohF9PhgrBmYMtpodpZzI6TrbDDcrtHqE-sSG1-RzJT6E8q_y4H-Z7bqsVsmYOhP0ahqY7esVXstr9K1Rly6RWjyIwjRgziOu-lLf6-bI0CaNfsbVvTTYmLbAgTU-9k7vPfpDKWZmQ5H8Rpdu3vBed2s3AiF8WmRDLCxJv9D5MBP6Pqnai6ss9AV-BYFawhx6Ve',
      freshnessPercent: 0.95,
      state: FreshnessState.fresh,
    ),
    Ingredient(
      name: '意式黑醋酱',
      quantity: '250ml',
      unit: '昨天添加',
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuCg6KYEF9YgLsLG3L9PC6xXaeXADor37AeWH7rJhzwGzpMBlG4EkALwlyqgQByFtpv-wNeT_SEneD8KUeDcqKQSklicxMIlNZ1xv6N9lp4ZBHLWQnGbIc8WW0gY8AEAxj2SdOZIwsw3Sw2TgylhlryPgSPmubY1PqQfE700twsvklWVva9zGyVlbqh1cd0gcTw-rgVWtqIn80I-hEAxTEBq4ZyV8gUR3rNSzlkx0tM-Aps6_SMYFniQgGCmRD8JJJfh4hj2DL8Kr8hJ',
      freshnessPercent: 1.0,
      state: FreshnessState.fresh,
    ),
  ];

  static const storageAreas = [
    StorageArea(
      name: '冰箱',
      icon: IconType.fridge,
      itemCount: 12,
      capacityPercent: 0.65,
    ),
    StorageArea(
      name: '食品柜',
      icon: IconType.pantry,
      itemCount: 42,
      capacityPercent: 0.88,
    ),
    StorageArea(
      name: '冷冻室',
      icon: IconType.freezer,
      itemCount: 8,
      capacityPercent: 0.30,
    ),
  ];

  static const shoppingItems = [
    ShoppingItem(
      id: 'si_1',
      name: '有机传家宝番茄',
      detail: '4个 \u2022 农贸市场',
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuCyl-JMJBY2Njmh12bRxReBwGYzEDEU40r3Dzx_IEnB273JLsd8Su0cmUfWc__Ug03OF3P-tr_ZmaqgAxL_h0eEyxxUsDZZZPo742nvnK4Z2_OkqkBzHoMg_-POhUqwlNBQKrRBqidGkP5sda341pJ0eBroXO59p-1ngNXf9q21-ut3qBKhqy1hayIp5TOSLaSYlrXEWLVbe-JS2U3eK9WccR7D61DinK5sivuNQWeV95mTgW0X0HCl4-dini8n-YScXfVW5Fjm7CJW',
      category: '新鲜蔬果',
    ),
    ShoppingItem(
      id: 'si_2',
      name: '野生芝麻菜',
      detail: '1袋 (250g)',
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuAROHAQCldb_AWPTk4yTm5yWl9P3JU7UHzh692wGEpTYPZGNJwVheUE6NMdIdJ_ntuTAz-mKcZlch1G_Y_013ohlVuoMhbpLJtM6Cx72lYWVqMDzOdd4w0v5ljdWM9PMpYqFVePfgTj_vEPa1nZ1dFBg-AicKNcUtCrHnrmNawJv0xzjOrCWWk4b23CLgfAEl_CCHDddCJ7cVFMf0R3joANABkTMJLNwaBiXSg12b2ABSwHn5gXAGKL_HQ1GpMkwRM-T6S4ntK6oaPO',
      category: '新鲜蔬果',
    ),
    ShoppingItem(
      id: 'si_3',
      name: '哈斯牛油果',
      detail: '2个 \u2022 已熟',
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuDloSiqJvtCnb8SYWz4KB4uH2qqCOQ9EfqAps1Xcwy7jsDrVd7VCZtYwdYO2e3F7k_4uXhPytXYcTmfpAJCKb87uC2AN2LVXWwVhaYYx3Wqzsqy140EHUQpA9XeSzHjASbmav1Gx5LmmlbEa_TOpe7Ek25sn5KuVXN64X4jW1N8cvRjN4_u7I61A8Fd2pqreWLh8LraZNMMVu9n8ieP7kHu6Whswojwq2tznJvqDynFhZh47nHckUY3zItO_T-0bwsk2UGHKJSiPZ5O',
      category: '新鲜蔬果',
    ),
    ShoppingItem(
      id: 'si_4',
      name: '马尔顿海盐片',
      detail: '1盒 (250g)',
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuAATtKQDkKxOKz7CIxmUZFUkyo4Vu2Uec_3krMuWpq6ZB3qCNFExil0BOnYXqn4lfEzMQI_8AvpWLBHC7vI_8mgHZ-HEEo1VIym_EOxD-cvmklhZmo0oF9XM-X0hDaKIafzqKPRP0hTjEUM41sER3Cas_dmP0FfnR33LJ9SM49GerBzFLvpGG11hH7xtChwdDcovRgseCjwL53Gc-miMObPkzkINV0pjSOOz7qtgeKl1cShJtKZY9rk7q9EoUPT2Tm0kJ1TtK7chR3_',
      category: '乳制品与干货',
      isChecked: true,
    ),
    ShoppingItem(
      id: 'si_5',
      name: 'A2全脂牛奶',
      detail: '1升',
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuBY_EugtkwfrvYPgizEYk-JaOZQkP8St-c8Yl4bVfQVVZ0us0Wf-4nnTVGw-QHR5quzqa_vauccgJ_ByurTYq-cgrS8tp5GHTWYYDYjk_yJbzhYweIDcpNEGRDNvKjjZLFehwMPItq9EHgetQzGm-t4GrfDX_RLoqYI1HeD2FRLR7wpTbQrdIz1qh1zdan2XxgxgyVhpB10lbFTIX-BD_mLuVWK-8971XPCkFkH3QsMMuFHCYxDWombc81UDTSfF5cGtq7XO0JNz7yf',
      category: '乳制品与干货',
    ),
  ];

  static const quickSuggestions = ['牛奶', '鸡蛋', '酸面包', '黄油'];
}
