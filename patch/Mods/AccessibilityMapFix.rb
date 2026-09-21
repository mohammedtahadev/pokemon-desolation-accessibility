# =============================================================================
# Pokemon Desolation Accessibility Pack - by Mohammed Taha (mohammedtahadev).
# AccessibilityMapFix.rb - one defensive guard on a base-game method.
#
# This is NOT an accessibility feature. It keeps the Accessibility* prefix only
# so that "delete the Accessibility*.rb files to revert everything" stays true.
#
# WHAT IT GUARDS
# --------------
# Scripts/Map.rb line 70, inside PokemonMapMetadata#updateMap:
#
#     for i in @movedEvents
#       if i[0][0]==$game_map.map_id && i[1]
#         next if !$game_map.events[i[0][1]]
#         ... move and turn the event ...
#       end
#       if i[1][3]!=nil                              # <-- outside the guard
#         $game_map.events[i[0][1]].through=i[1][3]
#       end
#     end
#
# The `through` assignment sits OUTSIDE the map-id check, so for an entry that
# belongs to a different map it either raises NoMethodError on nil, or - worse,
# because it is silent - overwrites the `through` flag of whatever unrelated
# event happens to share that numeric id on the map you are standing on. An
# event with `through` wrongly set walks through walls; wrongly cleared, it
# blocks a doorway.
#
# IS IT REACHABLE? NO - AND THAT MATTERS
# --------------------------------------
# It is not reachable in normal play, and this file is insurance, not a repair
# of something that is breaking today. Every path that changes $game_map fires
# Events.onMapChange, whose handler at Scripts/Field.rb:1818 calls
# $PokemonMap.clear and empties @movedEvents:
#
#   - walking through a door      MapFactory#setup -> setMapChanged
#   - crossing a map seam         MapFactory#setCurrentMap -> setMapChanged
#   - loading a save              PokemonMapFactory.new -> setup -> setMapChanged
#                                 (which is why Load.rb:688 deep-copies the hash
#                                  first, commented "last stand against
#                                  mapfactory")
#
# So by the time updateMap runs, @movedEvents only ever holds entries for the
# map you are actually on, and the unguarded line does the right thing by
# accident.
#
# The one route that is not proven safe is an old save: DataConversion.rb:47
# loads :PokemonMap straight out of a legacy save file, whatever shape it is
# in. That is the case this guards.
#
# WHAT CHANGED
# ------------
# The `through` assignment moved inside the map-id check, where the rest of the
# body already is. Nothing else - same iteration, same order, same effects. On
# every input reachable in normal play this behaves identically to the original.
# =============================================================================

class PokemonMapMetadata
  def updateMap
    for i in @erasedEvents
      if i[0][0] == $game_map.map_id && i[1]
        event = $game_map.events[i[0][1]]
        event.erase if event
      end
    end
    for i in @movedEvents
      if i[0][0] == $game_map.map_id && i[1]
        next if !$game_map.events[i[0][1]]
        $game_map.events[i[0][1]].moveto(i[1][0], i[1][1])
        case i[1][2]
        when 2
          $game_map.events[i[0][1]].turn_down
        when 4
          $game_map.events[i[0][1]].turn_left
        when 6
          $game_map.events[i[0][1]].turn_right
        when 8
          $game_map.events[i[0][1]].turn_up
        end
        # MOVED INSIDE THE GUARD. This is the whole fix.
        if i[1][3] != nil
          $game_map.events[i[0][1]].through = i[1][3]
        end
      end
    end
  end
end
