# Flutter→SwiftUI 迁移蓝图(自动测绘产出)

> workflow `map-flutter-for-swiftui` 生成,12 子系统。每文件:概述/组件/外部集成/Swift 映射/迁移注意/工作量/开放问题。

建议精读顺序:models → storage → services → sync → backend → bootstrap → widgets → screens-*

- [domain-models](blueprint/models.md) — 21 组件 · effort M
- [persistence-drift](blueprint/storage.md) — 21 组件 · effort L
- [state-providers](blueprint/providers.md) — 28 组件 · effort XL
- [supabase-sync](blueprint/sync.md) — 17 组件 · effort XL
- [services](blueprint/services.md) — 17 组件 · effort L
- [screens-inventory](blueprint/screens-core.md) — 23 组件 · effort XL
- [screens-recipes](blueprint/screens-recipes.md) — 23 组件 · effort XL
- [screens-shopping-meal-waste](blueprint/screens-flows.md) — 29 组件 · effort L
- [screens-auth-settings](blueprint/screens-auth.md) — 16 组件 · effort L
- [widgets-design-system](blueprint/widgets.md) — 65 组件 · effort XL
- [app-bootstrap-routing](blueprint/bootstrap.md) — 26 组件 · effort L
- [backend-supabase-api](blueprint/backend.md) — 17 组件 · effort L
