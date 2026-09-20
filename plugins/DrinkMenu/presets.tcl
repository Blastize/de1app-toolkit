#
# Drink Menu -- preset data (read-only, shipped with the plugin)
#
# Three dicts in the plugin namespace: ingredients, vessels, drinks.
# Nothing in the plugin ever writes back into them; derived values (total
# ml, tab membership) are computed on demand or cached in a separate
# runtime array. Sourced by DrinkMenu.tcl inside a catch; a failure here
# leaves all three empty and the menu shows "Presets failed to load".
#
# Every non-ASCII character is a \uXXXX escape (no literal UTF-8 in any
# source file). The dict bodies are wrapped in `subst -nocommands
# -novariables` so those escapes are substituted while braces, $ and [ ]
# stay literal.
#
# Vessel geometry (design units, see DrinkMenu.tcl vessel_geometry):
#   profile   {frac half_width ...} of the BOWL interior, floor (0) -> rim (1)
#   height    bowl height
#   handle    0/1, handle_w extra width to the right of the body
#   stem      {} or {stem_w stem_h foot_w foot_h}, drawn below the bowl;
#             layers never enter the stem
#   tile_scale 0.6-1.0, shrinks the fitted vessel so sizes stay
#             comparable at tile size (a demitasse reads smaller than a
#             highball, but neither is tiny). Pass 12 (A1) compressed the
#             ladder from 0.62..1.00 to 0.88..1.00 (same order, linearly
#             compressed): with the wider tile cup zone the old ladder
#             still left the demitasse at ~0.18 of the tile width.
#             Relative sizes still read (demitasse 0.88 < small glass
#             0.91 < cup 0.94 < large cup 0.96 < latte glass 0.97 <
#             coupe 0.98 < tall glass 1.00 = pint glass 1.00) but no
#             vessel is tiny any more. The pint (Pass 39) shares the tall
#             glass's 1.00: both are height-bound in a tile, so they read
#             the same height there and differ by their badge; the hero
#             and preview (use_tile_scale 0) show the true difference.
#

namespace eval ::plugins::DrinkMenu {

    variable ingredients [subst -nocommands -novariables {
        ristretto      {name "Ristretto"          color "#24130a" flags {hot coffee} role coffee}
        espresso       {name "Espresso"           color "#3a2114" flags {hot coffee} role coffee}
        brewed_coffee  {name "Brewed coffee"      color "#4a2e1b" flags {hot coffee} role coffee}
        hot_water      {name "Hot water"          color "#cfc4b4" flags {hot} role base}
        cold_water     {name "Cold water"         color "#a9c8dc" flags {cold} role base}
        tonic          {name "Tonic water"        color "#d7e6ec" flags {cold} role base}
        steamed_milk   {name "Steamed milk"       color "#efdfc4" flags {hot dairy} role base}
        milk_foam      {name "Milk foam"          color "#fbf5e8" flags {hot dairy} role base}
        hot_milk       {name "Hot milk"           color "#f0e2ca" flags {hot dairy} role base}
        cold_milk      {name "Cold milk"          color "#f2e6d0" flags {cold dairy} role base}
        cold_foam      {name "Cold foam"          color "#f7f1e6" flags {cold dairy} role base}
        half_half      {name "Half and half"      color "#efe0c5" flags {hot dairy} role base}
        whipped_cream  {name "Whipped cream"      color "#fff8ec" flags {dairy} role base}
        condensed_milk {name "Condensed milk"     color "#f3e2b8" flags {dairy} role base}
        hot_chocolate  {name "Hot chocolate"      color "#6a3a24" flags {hot} role base}
        chai           {name "Spiced chai"        color "#b26a3a" flags {hot} role base}
        ice_cream      {name "Vanilla ice cream"  color "#f7ecd2" flags {cold dairy} role base}
        ice            {name "Ice cubes"          color "#d6e9f1" flags {cold} role minor}
        sugar          {name "Sugar"              color "#f4ead6" flags {} role minor}
    }]

    variable vessels [subst -nocommands -novariables {
        demitasse   {name "Demitasse"          capacity 90  profile {0.0 22 1.0 34} height 60  handle 1 handle_w 16 stem {} tile_scale 0.88 size_up cup}
        cup         {name "Cappuccino cup"     capacity 200 profile {0.0 32 1.0 46} height 66  handle 1 handle_w 18 stem {} tile_scale 0.94 size_up large_cup}
        large_cup   {name "Large cup"          capacity 300 profile {0.0 36 1.0 52} height 74  handle 1 handle_w 20 stem {} tile_scale 0.96 size_up highball}
        tumbler     {name "Small glass"        capacity 120 profile {0.0 24 1.0 27} height 62  handle 0 handle_w 0  stem {} tile_scale 0.91 size_up latte_glass}
        latte_glass {name "Latte glass"        capacity 300 profile {0.0 21 1.0 24} height 100 handle 0 handle_w 0  stem {} tile_scale 0.97 size_up highball}
        highball    {name "Tall glass"         capacity 350 profile {0.0 22 1.0 25} height 118 handle 0 handle_w 0  stem {} tile_scale 1.00 size_up pint}
        martini     {name "Coupe glass"        capacity 180 profile {0.0 6 0.3 30 0.7 42 1.0 44} height 36 handle 0 handle_w 0 stem {6 30 36 6} tile_scale 0.98 size_up latte_glass}
        pint        {name "Pint glass"         capacity 500 profile {0.0 24 1.0 29} height 132 handle 0 handle_w 0  stem {} tile_scale 1.00 size_up pint}
    }]

    # Layers bottom -> top, ml. Group order = appendix order:
    # straight, water, milk_small, milk_cup, chocolate, cold.
    #
    # steps (Pass 14): 2 to 4 short imperative method lines per drink,
    # one line each, ASCII only, at most 58 characters, shown in the
    # detail page's Method card. They are source data like the layers:
    # nothing ever writes them back, and a custom drink made with
    # "Copy & edit" / "Save as copy" carries a COPY of its source's
    # steps into settings (exactly as the garnish is carried).
    variable drinks [subst -nocommands -novariables {
        ristretto          {name "Ristretto"            group straight   vessel demitasse   layers {ristretto 20} garnish {}
            steps {{Grind fine; 18 g in, 20 ml out in about 25 s.}
                   {Serve at once in a warm demitasse.}}}
        espresso           {name "Espresso"             group straight   vessel demitasse   layers {espresso 30} garnish {}
            steps {{Pull a single, 9 g in, 30 ml out, about 25 s.}
                   {Serve in a warm demitasse with the crema intact.}}}
        doppio             {name "Doppio"               group straight   vessel demitasse   layers {espresso 60} garnish {}
            steps {{Pull a doppio, 18 g in, 60 ml out, about 28 s.}
                   {Serve straight in a warm demitasse.}}}
        lungo              {name "Lungo"                group straight   vessel demitasse   layers {espresso 80} garnish {}
            steps {{Pull long: 18 g in, 80 ml out over 35 to 40 s.}
                   {Expect a thinner, more bitter cup than a doppio.}}}
        cafe_crema         {name "Caf\u00e9 crema"      group straight   vessel cup         layers {espresso 150} garnish {}
            steps {{Grind coarser than espresso, 16 g in the basket.}
                   {Pull 150 ml over about 60 s into a warm cup.}}}
        espresso_romano    {name "Espresso romano"      group straight   vessel demitasse   layers {espresso 30} garnish {lemon_slice}
            steps {{Pull a single, 9 g in, 30 ml out, about 25 s.}
                   {Rub the cup rim with a slice of lemon.}
                   {Serve the slice on the saucer.}}}
        cafe_cubano        {name "Caf\u00e9 Cubano"     group straight   vessel demitasse   layers {sugar 5 espresso 30} garnish {}
            steps {{Put 5 g of sugar in the cup before you pull.}
                   {Pull a single onto the sugar, 30 ml in 25 s.}
                   {Whip the sugar and first drops to a pale foam.}}}

        americano          {name "Americano"            group water      vessel cup         layers {espresso 60 hot_water 120} garnish {}
            steps {{Pull a doppio, 18 g in, 60 ml out, about 28 s.}
                   {Heat 120 ml of water to about 90 C.}
                   {Pour the water over the shot to keep the crema.}}}
        long_black         {name "Long black"           group water      vessel cup         layers {hot_water 120 espresso 60} garnish {}
            steps {{Pour 120 ml of hot water into the cup first.}
                   {Pull a doppio straight onto the water, 60 ml.}
                   {The crema stays on top; do not stir it in.}}}
        red_eye            {name "Red eye"              group water      vessel large_cup   layers {brewed_coffee 180 espresso 30} garnish {}
            steps {{Fill the cup with 180 ml of hot brewed coffee.}
                   {Pull a single, 30 ml, and pour it in.}
                   {Stir once and serve black.}}}
        black_eye          {name "Black eye"            group water      vessel large_cup   layers {brewed_coffee 180 espresso 60} garnish {}
            steps {{Fill the cup with 180 ml of hot brewed coffee.}
                   {Pull a doppio, 60 ml, and stir it through.}
                   {Strong and bitter: serve it without milk.}}}

        macchiato          {name "Macchiato"            group milk_small vessel demitasse   layers {espresso 30 milk_foam 15} garnish {}
            steps {{Pull a single, 9 g in, 30 ml out, about 25 s.}
                   {Steam a little milk to a dense, wet foam.}
                   {Spoon a 15 ml dollop of foam onto the shot.}}}
        cortado            {name "Cortado"              group milk_small vessel tumbler     layers {espresso 60 steamed_milk 60} garnish {}
            steps {{Pull a doppio, 18 g in, 60 ml out, about 28 s.}
                   {Steam 60 ml of milk to a thin, glossy texture.}
                   {Pour equal milk into the glass; almost no foam.}}}
        cortadito          {name "Cortadito"            group milk_small vessel tumbler     layers {sugar 5 espresso 30 hot_milk 30} garnish {}
            steps {{Put 5 g of sugar in the glass, pull 30 ml on it.}
                   {Whip the sugar and shot to a pale cream.}
                   {Top with 30 ml of hot milk and stir.}}}
        piccolo_latte      {name "Piccolo latte"        group milk_small vessel tumbler     layers {ristretto 20 steamed_milk 60 milk_foam 10} garnish {}
            steps {{Pull a ristretto, 18 g in, 20 ml out in 25 s.}
                   {Steam 70 ml of milk to a silky microfoam.}
                   {Pour into a small glass, 10 mm of foam on top.}}}
        cafe_noisette      {name "Caf\u00e9 noisette"   group milk_small vessel demitasse   layers {espresso 60 hot_milk 30} garnish {}
            steps {{Pull a doppio, 18 g in, 60 ml out, about 28 s.}
                   {Warm 30 ml of milk without foaming it.}
                   {Add milk until the cup turns hazelnut brown.}}}
        cafe_bombon        {name "Caf\u00e9 bomb\u00f3n" group milk_small vessel tumbler    layers {condensed_milk 30 espresso 30} garnish {}
            steps {{Pour 30 ml of condensed milk into a small glass.}
                   {Pull a single, 30 ml, slowly over the milk.}
                   {Serve unstirred so the two layers show.}}}
        espressino         {name "Espressino"           group milk_small vessel tumbler     layers {espresso 30 steamed_milk 30} garnish {cocoa}
            steps {{Dust cocoa inside the glass before you start.}
                   {Pull a single, 30 ml, then steam 30 ml of milk.}
                   {Pour the milk in and dust cocoa on top.}}}
        marocchino         {name "Marocchino"           group milk_small vessel tumbler     layers {espresso 30 milk_foam 30} garnish {cocoa}
            steps {{Dust cocoa in a small glass, then pull 30 ml.}
                   {Steam the milk hard to a dry, stiff foam.}
                   {Spoon 30 ml of foam over and dust with cocoa.}}}

        flat_white         {name "Flat white"           group milk_cup   vessel cup         layers {espresso 60 steamed_milk 120 milk_foam 8} garnish {}
            steps {{Pull a doppio, 18 g in, 60 ml out, about 28 s.}
                   {Steam 130 ml of milk to a thin, glossy microfoam.}
                   {Pour flat, 5 mm of foam, and free-pour the art.}}}
        cappuccino         {name "Cappuccino"           group milk_cup   vessel cup         layers {espresso 60 steamed_milk 60 milk_foam 60} garnish {}
            steps {{Pull a doppio, 18 g in, 60 ml out, about 28 s.}
                   {Steam 120 ml of milk to a thick, glossy foam.}
                   {Pour the milk over, then spoon foam to the rim.}
                   {Dust with cocoa if you like.}}}
        dry_cappuccino     {name "Dry cappuccino"       group milk_cup   vessel cup         layers {espresso 60 milk_foam 120} garnish {}
            steps {{Pull a doppio, 18 g in, 60 ml out, about 28 s.}
                   {Steam the milk hard to a dry, stiff foam.}
                   {Spoon 120 ml of foam on, leaving the liquid.}}}
        cafe_au_lait       {name "Caf\u00e9 au lait"    group milk_cup   vessel cup         layers {espresso 60 hot_milk 120} garnish {}
            steps {{Pull a doppio, 18 g in, 60 ml out, about 28 s.}
                   {Heat 120 ml of milk to 65 C without foaming.}
                   {Pour the milk and the coffee in together.}}}
        cafe_con_leche     {name "Caf\u00e9 con leche"  group milk_cup   vessel cup         layers {espresso 60 hot_milk 90} garnish {}
            steps {{Pull a doppio, 18 g in, 60 ml out, about 28 s.}
                   {Scald 90 ml of milk; do not foam it.}
                   {Pour the hot milk in and sweeten to taste.}}}
        breve              {name "Breve"                group milk_cup   vessel cup         layers {espresso 60 half_half 120} garnish {}
            steps {{Pull a doppio, 18 g in, 60 ml out, about 28 s.}
                   {Steam 120 ml of half and half gently to 60 C.}
                   {It scorches easily: keep the wand shallow.}}}
        galao              {name "Gal\u00e3o"           group milk_cup   vessel latte_glass layers {espresso 60 milk_foam 180} garnish {}
            steps {{Pull a doppio, 18 g in, 60 ml out, about 28 s.}
                   {Steam 180 ml of milk to a light, airy foam.}
                   {Pour into a tall glass, one coffee to three milk.}}}
        latte              {name "Latte"                group milk_cup   vessel latte_glass layers {espresso 60 steamed_milk 200 milk_foam 20} garnish {}
            steps {{Pull a doppio, 18 g in, 60 ml out, about 28 s.}
                   {Steam 220 ml of milk to a silky microfoam.}
                   {Pour into a latte glass, 10 mm of foam on top.}}}
        dirty_chai         {name "Dirty chai"           group milk_cup   vessel large_cup   layers {espresso 30 chai 120 steamed_milk 60 milk_foam 20} garnish {}
            steps {{Brew 120 ml of strong spiced chai.}
                   {Pull a single, 30 ml, and add it to the chai.}
                   {Steam 80 ml of milk and pour it over the top.}}}

        mocha              {name "Mocha"                group chocolate  vessel cup         layers {espresso 60 hot_chocolate 60 steamed_milk 60 whipped_cream 15} garnish {}
            steps {{Stir 60 ml of hot chocolate into the warm cup.}
                   {Pull a doppio, 60 ml, straight onto it.}
                   {Add 60 ml of steamed milk, then whipped cream.}}}
        mocha_breve        {name "Mocha breve"          group chocolate  vessel cup         layers {espresso 60 hot_chocolate 60 half_half 60} garnish {}
            steps {{Stir 60 ml of hot chocolate into the warm cup.}
                   {Pull a doppio, 60 ml, and mix it in.}
                   {Steam 60 ml of half and half and pour it over.}}}
        borgia             {name "Borgia"               group chocolate  vessel large_cup   layers {espresso 60 hot_chocolate 120 whipped_cream 40} garnish {orange_peel cinnamon}
            steps {{Warm 120 ml of hot chocolate with orange peel.}
                   {Pull a doppio, 60 ml, and stir it in.}
                   {Top with 40 ml of whipped cream and cinnamon.}
                   {Finish with a twist of orange peel.}}}
        espresso_con_panna {name "Espresso con panna"   group chocolate  vessel demitasse   layers {espresso 60 whipped_cream 30} garnish {}
            steps {{Pull a doppio, 18 g in, 60 ml out, about 28 s.}
                   {Spoon 30 ml of cold whipped cream on top.}
                   {Serve at once, unstirred.}}}
        vienna             {name "Vienna"               group chocolate  vessel cup         layers {espresso 60 whipped_cream 40} garnish {}
            steps {{Pull a doppio, 18 g in, 60 ml out, about 28 s.}
                   {Whip 40 ml of cream to soft peaks.}
                   {Float the cream so the coffee stays under it.}}}

        iced_latte         {name "Iced latte"           group cold       vessel highball    layers {ice 80 cold_milk 200 espresso 60} garnish {}
            steps {{Fill a tall glass with 80 ml of ice cubes.}
                   {Pour in 200 ml of cold milk.}
                   {Pull a doppio, 60 ml, and pour it over slowly.}}}
        iced_americano     {name "Iced americano"       group cold       vessel highball    layers {ice 80 cold_water 120 espresso 60} garnish {}
            steps {{Fill a tall glass with 80 ml of ice cubes.}
                   {Add 120 ml of cold water.}
                   {Pull a doppio, 60 ml, and pour it over the ice.}}}
        iced_mocha         {name "Iced mocha"           group cold       vessel highball    layers {ice 80 hot_chocolate 60 cold_milk 150 espresso 60} garnish {}
            steps {{Stir 60 ml of hot chocolate into 150 ml of milk.}
                   {Fill a tall glass with 80 ml of ice, add the milk.}
                   {Pull a doppio, 60 ml, and pour it over.}}}
        cafe_con_hielo     {name "Caf\u00e9 con hielo"  group cold       vessel tumbler     layers {ice 60 espresso 60} garnish {}
            steps {{Fill a small glass with 60 ml of ice cubes.}
                   {Pull a doppio, 60 ml, into a separate cup.}
                   {Sweeten it, then pour it over the ice.}}}
        affogato           {name "Affogato"             group cold       vessel cup         layers {ice_cream 90 espresso 60} garnish {}
            steps {{Put 90 ml of vanilla ice cream in a cold cup.}
                   {Pull a doppio, 18 g in, 60 ml out, about 28 s.}
                   {Pour it over the ice cream and serve at once.}}}
        espresso_tonic     {name "Espresso tonic"       group cold       vessel highball    layers {ice 80 tonic 150 espresso 60} garnish {}
            steps {{Fill a tall glass with 80 ml of ice cubes.}
                   {Add 150 ml of cold tonic water.}
                   {Pull a doppio, 60 ml, and pour it slowly over.}}}
        shakerato          {name "Shakerato"            group cold       vessel martini     layers {sugar 5 espresso 60 cold_foam 30} garnish {}
            steps {{Pull a doppio, 60 ml, over 5 g of sugar.}
                   {Shake it hard with ice for 20 s until foamy.}
                   {Strain into a chilled coupe, no ice.}}}
        freddo_espresso    {name "Freddo espresso"      group cold       vessel highball    layers {ice 80 espresso 60 cold_foam 20} garnish {}
            steps {{Pull a doppio, 60 ml, and sweeten it now.}
                   {Shake or whisk it with ice until frothy.}
                   {Pour over 80 ml of fresh ice in a tall glass.}}}
        freddo_cappuccino  {name "Freddo cappuccino"    group cold       vessel highball    layers {ice 80 espresso 60 cold_foam 80} garnish {}
            steps {{Pull a doppio, 60 ml, and chill it with ice.}
                   {Whisk 80 ml of cold milk to a thick cold foam.}
                   {Pour the coffee over ice, then float the foam.}}}
        ca_phe_sua_da      {name "C\u00e0 ph\u00ea s\u1eefa \u0111\u00e1" group cold vessel tumbler layers {condensed_milk 30 espresso 60 ice 30} garnish {}
            steps {{Pour 30 ml of condensed milk into the glass.}
                   {Pull a doppio, 60 ml, straight onto the milk.}
                   {Stir it well, then add 30 ml of ice.}}}
    }]

    # Appendix group order, used by visible_drinks.
    variable group_order {straight water milk_small milk_cup chocolate cold}
}
