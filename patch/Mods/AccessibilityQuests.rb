# =============================================================================
# Pokemon Desolation Accessibility Pack - by Mohammed Taha (mohammedtahadev).
# AccessibilityQuests.rb - Desolation's quest log, by ear.
#
# The quest log is Desolation's own feature (Scripts/Pokemon Desolation/
# Quest_Log.rb), opened from the Pokegear. Three of its four parts already
# spoke before this mod existed, because they are ordinary command windows:
# the Pokegear menu, the quest list rows, and the Back entry. What stayed
# silent:
#
#   The Main/Side tab     LEFT/RIGHT flips a boolean and redraws a bitmap
#                         header; the list's remembered index usually does not
#                         change, so the menu hook has nothing to react to.
#   The quest DETAIL page there is no selectable window on it at all - the
#                         title and every objective are separate plain text
#                         sprites, paged with LEFT/RIGHT.
#   Quest updates on the  "Quest Added / In Progress / Completed" appears as a
#   map                   sliding toast sprite while you play. Completely
#                         silent, and easily the most important of the three.
#
# DATA SHAPE (from Quest_Log.rb): each quest is a plain array -
#   [0] title, [1] state as a STRING "0"/"1"/"2" (undiscovered/in progress/
#   complete), [2] objectives as [state, text] pairs, [3] "true"/"false" for
#   main/side. Objectives with state 0 are not drawn, so they are not spoken
#   either - the log never spoils steps you have not reached.
# =============================================================================

module A11yQuests
  STATE_WORDS = { "0" => "undiscovered", "1" => "in progress", "2" => "completed" }

  class << self
    def say(text, interrupt: true)
      return unless defined?(AccessibilitySpeech)
      AccessibilitySpeech.speak(text.to_s, true, interrupt: interrupt)
    rescue Exception
      nil
    end

    def queue(text)
      say(text, interrupt: false)
    end
  end
end

# ---------------------------------------------------------------------------
# The Main/Side tab flip. pbSetCommands is called exactly when the tab changes
# (and once at scene start), with the rebuilt list.
# ---------------------------------------------------------------------------
if defined?(QuestLog_Scene)
  class QuestLog_Scene
    unless method_defined?(:a11y_quests_set_commands)
      alias_method :a11y_quests_set_commands, :pbSetCommands
      def pbSetCommands(newcommands, newindex)
        result = a11y_quests_set_commands(newcommands, newindex)
        begin
          # The subheader sprite is the authority on which tab this is - the
          # underlying boolean's naming is confusing enough that reading the
          # same text the sighted player sees is the only safe answer.
          tab = (@sprites["subheader"].text rescue nil)
          tab = ($game_variables[:QuestLogMainOrSide] ? "Main Quests" : "Side Quests") if tab.to_s.empty?
          A11yQuests.say(tab)
          # Let the selected row follow the tab name.
          w = @sprites["commands"]
          w.instance_variable_set(:@a11y_announced, false) if w
        rescue Exception
        end
        result
      end
    end
  end
end

# ---------------------------------------------------------------------------
# The detail page. createSprites runs when the page opens AND on every
# LEFT/RIGHT page turn, and @currentlog/@index/@screens hold everything the
# sighted player is looking at.
# ---------------------------------------------------------------------------
if defined?(QuestInfo_Scene)
  class QuestInfo_Scene
    unless method_defined?(:a11y_quests_create_sprites)
      alias_method :a11y_quests_create_sprites, :createSprites
      def createSprites(*args)
        result = a11y_quests_create_sprites(*args)
        begin
          log = instance_variable_get(:@currentlog)
          quest = log && log[@index]
          if quest
            title = quest[0].to_s
            state = A11yQuests::STATE_WORDS[quest[1].to_s] || quest[1].to_s
            A11yQuests.say("#{title}, #{state}.")
            Array(quest[2]).each do |goal|
              st = goal[0].to_i
              next if st == 0                       # not revealed - not spoiled
              prefix = st == 2 ? "Done: " : ""
              A11yQuests.queue("#{prefix}#{goal[1]}")
            end
            if @scrolling && @screens && @screens.length > 1
              A11yQuests.queue("Page #{@screen_index + 1} of #{@screens.length}. Left and right turn pages.")
            end
          end
        rescue Exception
        end
        result
      end
    end
  end
end

# ---------------------------------------------------------------------------
# The on-map toast. pbSetQuestGoal is the single place quest progress changes,
# and it ends by sliding a LocationWindow across the screen - a sprite, and
# nothing else. Say the same thing it shows. When the game asks for no popup,
# there is no speech either: silent means silent.
# ---------------------------------------------------------------------------
if defined?(pbSetQuestGoal) || (respond_to?(:pbSetQuestGoal, true) rescue false)
  unless (respond_to?(:a11y_quests_set_goal, true) rescue false)
    alias a11y_quests_set_goal pbSetQuestGoal
    def pbSetQuestGoal(title, goal, newstate, shouldrevealnextgoal = false, shouldcomplete = false, nopopup = false)
      # The word the toast will use depends on the state BEFORE the change.
      before = begin
        q = $game_variables[:QuestLog].detect { |qq| qq[0].downcase == title.downcase }
        q ? q[1].to_s : "0"
      rescue Exception
        nil
      end
      result = a11y_quests_set_goal(title, goal, newstate, shouldrevealnextgoal, shouldcomplete, nopopup)
      begin
        unless nopopup
          after = begin
            q = $game_variables[:QuestLog].detect { |qq| qq[0].downcase == title.downcase }
            q ? q[1].to_s : nil
          rescue Exception
            nil
          end
          word = if after == "2"
                   "completed"
                 elsif before.nil? || before == "0"
                   "added"
                 else
                   "updated"
                 end
          A11yQuests.queue("Quest #{word}: #{title}")
        end
      rescue Exception
      end
      result
    end
  end
end
