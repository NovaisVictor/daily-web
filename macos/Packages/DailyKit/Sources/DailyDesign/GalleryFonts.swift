import SwiftUI

/// Geist next to SF for every type role, plus Geist Mono, to check the switch by eye.
/// Sample text only.
struct FontsGallery: View {
  private let sample = "Reunião às 14:30 · 1.234 tarefas"

  var body: some View {
    ScrollView {
      Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 12) {
        GridRow {
          Text("Papel")
          Text("Geist")
          Text("SF (antes)")
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        ForEach(TypeRole.allCases, id: \.self) { role in
          GridRow {
            Text(role.rawValue).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(sample).typeRole(role)
            Text(sample)
              .font(.system(size: role.size, weight: role.weight))
              .tracking(role.tracking)
          }
        }
        Divider()
        GridRow {
          Text("mono").font(.system(size: 11)).foregroundStyle(.secondary)
          Text("git commit -m \"fix: 0123456789\"").font(.dailyMono(size: 14))
          Text("git commit -m \"fix: 0123456789\"").font(.system(size: 14, design: .monospaced))
        }
        GridRow {
          Text("mono 600").font(.system(size: 11)).foregroundStyle(.secondary)
          Text("PROJ-1234").font(.dailyMono(size: 14, weight: .semibold))
          Text("PROJ-1234").font(.system(size: 14, weight: .semibold, design: .monospaced))
        }
      }
      .padding(24)
    }
  }
}

#Preview("Fontes · claro") { FontsGallery().frame(width: 1100, height: 700).environment(\.colorScheme, .light) }
#Preview("Fontes · escuro") {
  FontsGallery().frame(width: 1100, height: 700).background(.black).environment(\.colorScheme, .dark)
}
