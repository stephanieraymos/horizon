import Foundation
import Supabase

// Horizon shares the family backend with TheGlade and Orbit.
// Project ref: ihvljgwfslxorxsorzpi. The publishable key is client-safe by design.
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://ihvljgwfslxorxsorzpi.supabase.co")!,
    supabaseKey: "sb_publishable_R7d36YikY9beUIolCZt0Fw_4agU2MLz"
)
