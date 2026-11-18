using HarmonyLib;
using System;
using System.Runtime.CompilerServices;
using UnityEngine;

namespace DragoonCapes
{
    internal class ShamanCape
    {
        // Attack is cloned for each cast. Keep the health shortfall on that cast
        // rather than modifying the shared weapon or its resource costs.
        private sealed class EitrShortfall
        {
            public EitrShortfall() { }
            public float HealthCost;
        }

        private static readonly ConditionalWeakTable<Attack, EitrShortfall> Shortfalls =
            new ConditionalWeakTable<Attack, EitrShortfall>();

        [HarmonyPatch]
        private static class ShamanPatch
        {
            // This getter feeds the initial Eitr check and the actual Eitr spend.
            // Recalculate per call so burst attacks can convert each burst too.
            [HarmonyPostfix]
            [HarmonyPatch(typeof(Attack), nameof(Attack.GetAttackEitr),
                new Type[] { typeof(Character), typeof(ItemDrop.ItemData) })]
            private static void GetAttackEitr_Postfix(Attack __instance, Character character,
                ItemDrop.ItemData weapon, ref float __result)
            {
                Player player = character as Player;
                if (player == null || player.IsDead() || weapon == null ||
                    __instance.GetWeapon() != weapon ||
                    !player.GetSEMan().HaveStatusEffectCategory("ShamanCape") || __result <= 0f)
                {
                    Shortfalls.Remove(__instance);
                    return;
                }

                // TryUseEitr requires an extra 0.1 Eitr for positive costs.
                // Reserve a small margin so a zero-Eitr player can still cast.
                float eitrToUse = Mathf.Min(__result, Mathf.Max(0f, player.GetEitr() - 0.11f));
                float healthCost = __result - eitrToUse;
                if (healthCost <= 0f)
                {
                    Shortfalls.Remove(__instance);
                    return;
                }

                Shortfalls.GetOrCreateValue(__instance).HealthCost = healthCost;
                __result = eitrToUse;
            }

            // Valheim consumes health after Eitr and uses this getter for both
            // the initial check and actual charge. Preserve existing health costs.
            [HarmonyPostfix]
            [HarmonyPatch(typeof(Attack), "GetAttackHealth")]
            private static void GetAttackHealth_Postfix(Attack __instance, ref float __result)
            {
                if (Shortfalls.TryGetValue(__instance, out EitrShortfall shortfall))
                {
                    __result += shortfall.HealthCost;
                }
            }
        }
    }
}
