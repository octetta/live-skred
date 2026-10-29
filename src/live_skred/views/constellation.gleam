//// # Orbital Voice Constellation View (Lustre SVG)
////
//// Renders the 16-voice reactive orbital constellation driven by
//// Skred's real-time control plane events.

import gleam/float
import gleam/int
import gleam/list
import live_skred/types.{type VoiceNode}
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/svg

const center_x = 200.0
const center_y = 200.0
const orbit_radius = 140.0
const pi = 3.141592653589793

/// Calculates (x, y) coordinates on the orbit for voice index 0..15.
fn voice_coordinates(index: Int) -> #(Float, Float) {
  // Voice 0 starts at top (-PI/2) and goes clockwise
  let angle = -0.5 *. pi +. {int.to_float(index) *. {2.0 *. pi /. 16.0}}
  let x = center_x +. {orbit_radius *. float_cos(angle)}
  let y = center_y +. {orbit_radius *. float_sin(angle)}
  #(x, y)
}

/// Helper float approximations for SVG positioning
fn float_cos(rad: Float) -> Float {
  // Simple trigonometric lookup / approximation
  let norm = float_wrap(rad, -1.0 *. pi, pi)
  1.0 -. {norm *. norm /. 2.0} +. {norm *. norm *. norm *. norm /. 24.0}
}

fn float_sin(rad: Float) -> Float {
  let norm = float_wrap(rad, -1.0 *. pi, pi)
  norm -. {norm *. norm *. norm /. 6.0} +. {norm *. norm *. norm *. norm *. norm /. 120.0}
}

fn float_wrap(val: Float, min_val: Float, max_val: Float) -> Float {
  let range = max_val -. min_val
  let offset = val -. min_val
  let rem = case range >. 0.0 {
    True -> {
      let turns = float.floor(offset /. range)
      offset -. {turns *. range}
    }
    False -> 0.0
  }
  rem +. min_val
}

/// Returns a color for the voice node based on its instrument role.
fn voice_color(voice_id: Int, is_active: Bool) -> String {
  case voice_id {
    // 0..3: Kick & Bass (Warm Crimson / Orange)
    0 | 1 | 2 | 3 ->
      case is_active {
        True -> "#ff5722"
        False -> "#e64a19"
      }
    // 4..7: Percussion & Hats (Neon Cyan)
    4 | 5 | 6 | 7 ->
      case is_active {
        True -> "#00e5ff"
        False -> "#00b0ff"
      }
    // 8..11: Leads & Synths (Electric Purple)
    8 | 9 | 10 | 11 ->
      case is_active {
        True -> "#d500f9"
        False -> "#aa00ff"
      }
    // 12..15: Poly & Aux (Emerald Green)
    _ ->
      case is_active {
        True -> "#00e676"
        False -> "#00c853"
      }
  }
}

/// Renders a single voice node.
fn render_voice_node(node: VoiceNode) -> Element(a) {
  let #(cx, cy) = voice_coordinates(node.id)
  let color = voice_color(node.id, node.active)
  let base_radius = case node.active {
    True -> 16.0 +. {node.velocity *. 8.0}
    False -> 12.0
  }
  let opacity_str = case node.active {
    True -> "1.0"
    False -> "0.35"
  }

  svg.g([class("voice-node")], [
    // Outer glow halo if active
    case node.active {
      True ->
        svg.circle([
          attribute.attribute("cx", float.to_string(cx)),
          attribute.attribute("cy", float.to_string(cy)),
          attribute.attribute("r", float.to_string(base_radius +. 8.0)),
          attribute.attribute("fill", "none"),
          attribute.attribute("stroke", color),
          attribute.attribute("stroke-width", "2"),
          attribute.attribute("opacity", "0.6"),
          class("pulse-halo"),
        ])
      False -> svg.g([], [])
    },
    // Main circular node
    svg.circle([
      attribute.attribute("cx", float.to_string(cx)),
      attribute.attribute("cy", float.to_string(cy)),
      attribute.attribute("r", float.to_string(base_radius)),
      attribute.attribute("fill", color),
      attribute.attribute("opacity", opacity_str),
      attribute.attribute("stroke", "#ffffff"),
      attribute.attribute("stroke-width", case node.active {
        True -> "2"
        False -> "1"
      }),
      class("node-circle"),
    ]),
    // Voice label text (v0, v1, etc.)
    svg.text(
      [
        attribute.attribute("x", float.to_string(cx)),
        attribute.attribute("y", float.to_string(cy +. 4.0)),
        attribute.attribute("text-anchor", "middle"),
        attribute.attribute("font-size", "10px"),
        attribute.attribute("font-weight", "bold"),
        attribute.attribute("fill", case node.active {
          True -> "#0d1117"
          False -> "#c9d1d9"
        }),
      ],
      "v" <> int.to_string(node.id),
    ),
  ])
}

/// Renders the complete Orbital Voice Constellation SVG widget.
pub fn view_constellation(
  voices: List(VoiceNode),
  active_count: Int,
  master_db: Float,
) -> Element(a) {
  svg.svg(
    [
      attribute.attribute("viewBox", "0 0 400 400"),
      class("orbital-constellation-svg"),
    ],
    [
      // Background orbital grid circles
      svg.circle([
        attribute.attribute("cx", float.to_string(center_x)),
        attribute.attribute("cy", float.to_string(center_y)),
        attribute.attribute("r", float.to_string(orbit_radius)),
        attribute.attribute("fill", "none"),
        attribute.attribute("stroke", "#30363d"),
        attribute.attribute("stroke-dasharray", "4 4"),
        attribute.attribute("stroke-width", "1.5"),
      ]),
      svg.circle([
        attribute.attribute("cx", float.to_string(center_x)),
        attribute.attribute("cy", float.to_string(center_y)),
        attribute.attribute("r", float.to_string(orbit_radius -. 40.0)),
        attribute.attribute("fill", "none"),
        attribute.attribute("stroke", "#21262d"),
        attribute.attribute("stroke-width", "1"),
      ]),

      // Center HUD display
      svg.circle([
        attribute.attribute("cx", float.to_string(center_x)),
        attribute.attribute("cy", float.to_string(center_y)),
        attribute.attribute("r", "50"),
        attribute.attribute("fill", "#161b22"),
        attribute.attribute("stroke", "#30363d"),
        attribute.attribute("stroke-width", "2"),
      ]),
      svg.text(
        [
          attribute.attribute("x", float.to_string(center_x)),
          attribute.attribute("y", float.to_string(center_y -. 10.0)),
          attribute.attribute("text-anchor", "middle"),
          attribute.attribute("font-size", "12px"),
          attribute.attribute("font-weight", "600"),
          attribute.attribute("fill", "#58a6ff"),
        ],
        "SKRED 0.80",
      ),
      svg.text(
        [
          attribute.attribute("x", float.to_string(center_x)),
          attribute.attribute("y", float.to_string(center_y +. 10.0)),
          attribute.attribute("text-anchor", "middle"),
          attribute.attribute("font-size", "14px"),
          attribute.attribute("font-weight", "bold"),
          attribute.attribute("fill", case active_count > 0 {
            True -> "#3fb950"
            False -> "#8b949e"
          }),
        ],
        int.to_string(active_count) <> " / 16 ACTIVE",
      ),
      svg.text(
        [
          attribute.attribute("x", float.to_string(center_x)),
          attribute.attribute("y", float.to_string(center_y +. 26.0)),
          attribute.attribute("text-anchor", "middle"),
          attribute.attribute("font-size", "10px"),
          attribute.attribute("fill", "#8b949e"),
        ],
        float.to_string(master_db) <> " dB",
      ),

      // Voice Nodes
      svg.g([], list.map(voices, render_voice_node)),
    ],
  )
}
