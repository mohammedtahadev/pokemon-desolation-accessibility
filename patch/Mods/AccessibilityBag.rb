# =============================================================================
# Pokemon Desolation Accessibility Pack - by Mohammed Taha (mohammedtahadev).
# AccessibilityBag.rb - the parts of the bag the menu hook cannot see.
#
# The item LIST already speaks: Window_PokemonBag descends from
# SpriteWindow_Selectable, so AccessibilityMenus announces every row - name and
# quantity - as you arrow through it. What stays silent is everything the bag
# does OUTSIDE that window's index:
#
#   Pocket switching   LEFT/RIGHT changes pocket in a hand-rolled input loop
#                      (Bag.rb pbChooseItem). The pocket name is drawn onto a
#                      plain bitmap sprite; usually not even the row index
#                      changes, so the hook has nothing to say.
#   Item description   drawn into a non-selectable text window on every cursor
#                      move; reading it aloud EVERY move would bury the list,
#                      so it goes on a key instead.
#   Sorting            the X key re-sorts the pocket with zero feedback.
#   Quantity choosing  Toss and the PC item screens pick a number with
#                      LEFT/RIGHT/UP/DOWN written straight into a text sprite.
#
# KEYS
#   N   read the selected item's full description (bag and PC item screens) -
#       the same "tell me more" key as notes in the pathfinder.
#
# WHY pbChooseNumber IS COPIED RATHER THAN HOOKED
# -----------------------------------------------
# The quantity chooser is one self-contained module function with its own
# input loop and a local variable for the number; there is no seam to hook
# from outside. It is copied verbatim from Bag.rb:1514 with four speech lines
# added at the points the number changes. Fifty lines, version-pinned to
# 6.0.13 like everything else here.
# =============================================================================

module A11yBag
  POCKET_NUMPAD = {}

  class << self
    def say(text, interrupt: true)
      return unless defined?(AccessibilitySpeech)
      AccessibilitySpeech.speak(text.to_s, true, interrupt: interrupt)
    rescue Exception
      nil
    end

    def pocket_name(pocket)
      names = (PokemonBag.pocketNames rescue nil)
      n = names && names[pocket]
      (n && !n.to_s.empty?) ? n : "Pocket #{pocket}"
    end

    # The description of whatever a bag-style window has selected.
    def describe_item(win)
      item = (win.item rescue nil)
      if item.nil?
        say("Close bag.")
        return
      end
      d = ($cache.items[item].desc rescue nil)
      name = ($cache.items[item].name rescue item.to_s)
      say(d && !d.to_s.empty? ? "#{name}. #{d}" : name)
      # A TM or HM teaches a move, and the sighted player gets per-party icons
      # saying who can learn it. Read the same verdicts, by name.
      begin
        move = ($cache.items[item].move rescue nil)
        if move && defined?(PokemonBag) && PokemonBag.respond_to?(:pbPartyCanLearnThisMove?)
          verdicts = PokemonBag.pbPartyCanLearnThisMove?(move)
          able, knows, unable = [], [], []
          Array(verdicts).each_with_index do |v, i|
            pk = ($Trainer.party[i] rescue nil)
            next unless pk
            n = (pk.name rescue "number #{i + 1}")
            case v
            when 1 then able << n
            when 2 then knows << n
            when 0 then unable << n
            end
          end
          say("Can learn: #{able.join(", ")}.", interrupt: false) unless able.empty?
          say("Already knows it: #{knows.join(", ")}.", interrupt: false) unless knows.empty?
          say("Cannot learn: #{unable.join(", ")}.", interrupt: false) unless unable.empty?
        end
      rescue Exception
      end
    rescue Exception
      nil
    end
  end
end

# ---------------------------------------------------------------------------
# Pocket switching: announce the pocket, then let the row re-announce itself.
# ---------------------------------------------------------------------------
if defined?(Window_PokemonBag)
  class Window_PokemonBag
    if method_defined?(:pocket=) && !method_defined?(:a11y_bag_pocket_set)
      alias_method :a11y_bag_pocket_set, :pocket=
      def pocket=(value)
        old = (self.pocket rescue nil)
        result = a11y_bag_pocket_set(value)
        begin
          if self.pocket != old
            A11yBag.say("#{A11yBag.pocket_name(self.pocket)} pocket")
            # The remembered index in the new pocket is often the same number,
            # so index= says nothing on its own. This is the menus mod's own
            # re-announce flag; clearing it makes the current row speak, after
            # the pocket name.
            instance_variable_set(:@a11y_announced, false)
          end
        rescue Exception
        end
        result
      end
    end

    # N: the full description, on demand.
    if method_defined?(:update) && !method_defined?(:a11y_bag_update)
      alias_method :a11y_bag_update, :update
      def update
        a11y_bag_update
        begin
          if self.active && Input.triggerex?(0x4E)      # N
            A11yBag.describe_item(self)
          end
        rescue Exception
        end
      end
    end
  end
end

# The PC item box list gets the same N key.
if defined?(Window_PokemonItemStorage)
  class Window_PokemonItemStorage
    if method_defined?(:update) && !method_defined?(:a11y_bag_storage_update)
      alias_method :a11y_bag_storage_update, :update
      def update
        a11y_bag_storage_update
        begin
          if self.active && Input.triggerex?(0x4E)      # N
            A11yBag.describe_item(self)
          end
        rescue Exception
        end
      end
    end
  end
end

# ---------------------------------------------------------------------------
# Sorting: the X key re-sorts the pocket and, until now, said nothing at all.
# ---------------------------------------------------------------------------
if defined?(PokemonBag_Scene)
  class PokemonBag_Scene
    if method_defined?(:pbHandleSortByType) && !method_defined?(:a11y_bag_sort)
      alias_method :a11y_bag_sort, :pbHandleSortByType
      def pbHandleSortByType(*args)
        result = a11y_bag_sort(*args)
        A11yBag.say("Pocket sorted.")
        result
      end
    end
  end
end

# ---------------------------------------------------------------------------
# The quantity chooser, copied from Bag.rb:1514 with speech at each change.
# ---------------------------------------------------------------------------
if defined?(UIHelper) && UIHelper.respond_to?(:pbChooseNumber)
  module UIHelper
    def self.pbChooseNumber(helpwindow,helptext,maximum)
      oldvisible=helpwindow.visible
      helpwindow.visible=true
      helpwindow.text=helptext
      helpwindow.letterbyletter=false
      curnumber=1
      ret=0
      A11yBag.say("#{helptext} 1 of #{maximum}. Up and down change by one, left and right by ten.", interrupt: false)
      using_block(numwindow=Window_UnformattedTextPokemon.new("x000")){
         numwindow.viewport=helpwindow.viewport
         numwindow.letterbyletter=false
         numwindow.text=_ISPRINTF("x{1:03d}",curnumber)
         numwindow.resizeToFit(numwindow.text,480)
         pbBottomRight(numwindow) # Move number window to the bottom right
         helpwindow.resizeHeightToFit(helpwindow.text,480-numwindow.width)
         pbBottomLeft(helpwindow) # Move help window to the bottom left
         loop do
           Graphics.update
           Input.update
           numwindow.update
           block_given? ? yield : helpwindow.update
           if Input.repeat?(Input::LEFT)
             curnumber-=10
             curnumber=1 if curnumber<1
             numwindow.text=_ISPRINTF("x{1:03d}",curnumber)
             pbPlayCursorSE()
             A11yBag.say(curnumber.to_s)
           elsif Input.repeat?(Input::RIGHT)
             curnumber+=10
             curnumber=maximum if curnumber>maximum
             numwindow.text=_ISPRINTF("x{1:03d}",curnumber)
             pbPlayCursorSE()
             A11yBag.say(curnumber.to_s)
           elsif Input.repeat?(Input::UP)
             curnumber+=1
             curnumber=1 if curnumber>maximum
             numwindow.text=_ISPRINTF("x{1:03d}",curnumber)
             pbPlayCursorSE()
             A11yBag.say(curnumber.to_s)
           elsif Input.repeat?(Input::DOWN)
             curnumber-=1
             curnumber=maximum if curnumber<1
             numwindow.text=_ISPRINTF("x{1:03d}",curnumber)
             pbPlayCursorSE()
             A11yBag.say(curnumber.to_s)
           elsif Input.trigger?(Input::C)
             ret=curnumber
             pbPlayDecisionSE()
             break
           elsif Input.trigger?(Input::B)
             ret=0
             pbPlayCancelSE()
             break
           end
         end
      }
      helpwindow.visible=oldvisible
      return ret
    end
  end
end
