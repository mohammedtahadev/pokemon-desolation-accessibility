# =============================================================================
# AccessibilityShop.rb - the Poke Mart, beyond its item list.
#
# The item LIST already speaks: Window_PokemonMart is a selectable window, so
# AccessibilityMenus reads every row - name and price - as you arrow. The rest
# of the shop draws its words into its own text boxes and was silent (a
# player report, Redcliff Town's shop):
#
#   How many?          the quantity chooser has its own input loop and writes
#                      the number, total price and "In Bag" count into boxes.
#   Shop messages      "That will be $600. OK?", "Here you are! Thank you!",
#                      "You don't have enough money." go through the shop
#                      scene's own pbDisplay / pbDisplayPaused / pbConfirm,
#                      not the game's message box that the speech mod reads.
#   Money              drawn in the corner, never spoken.
#   Item description   drawn beside the list on every cursor move.
#
# WHAT YOU HEAR NOW
#   Entering the shop  your money, after the first item.
#   Choosing how many  the question, then "1, $200. 3 in your bag. You have
#                      $4,500." - and every change: "5, $1,000".
#   Every shop message, the Yes/No question included.
#   After buying or selling, your new total.
#
# KEYS
#   N   in the item list: the item's full description - the same key as in
#       the bag.
#
# pbChooseNumber is copied from Mart.rb:165 rather than hooked, for the same
# reason as the bag's: the number lives in a local variable inside its own
# loop, with no seam to hook from outside. Version-pinned to 6.0.13.
# =============================================================================

module A11yShop
  class << self
    def say(text, interrupt: true)
      return unless defined?(AccessibilitySpeech)
      t = text.to_s.gsub(/\r?\n/, " ").gsub(/\s+/, " ").strip
      return if t.empty?
      AccessibilitySpeech.speak(t, true, interrupt: interrupt)
    rescue Exception
      nil
    end

    def money(n)
      "$#{defined?(pbCommaNumber) ? pbCommaNumber(n) : n}"
    rescue Exception
      "$#{n}"
    end

    # "5, $1,000" - the number, then what that many costs.
    def amount_line(count, unit_price)
      "#{count}, #{money(count * unit_price)}"
    end
  end
end

if defined?(PokemonMartScene)
  class PokemonMartScene
    # ── The shop's own message functions ───────────────────────────────────
    if method_defined?(:pbDisplay) && !method_defined?(:a11y_shop_display)
      alias_method :a11y_shop_display, :pbDisplay
      def pbDisplay(msg, brief = false)
        A11yShop.say(msg)
        a11y_shop_display(msg, brief)
      end
    end

    if method_defined?(:pbDisplayPaused) && !method_defined?(:a11y_shop_display_paused)
      alias_method :a11y_shop_display_paused, :pbDisplayPaused
      def pbDisplayPaused(msg)
        A11yShop.say(msg)
        a11y_shop_display_paused(msg)
      end
    end

    # The Yes/No window after it is read by the menus mod, whose first line
    # queues rather than interrupts - so the question is heard in full first.
    if method_defined?(:pbConfirm) && !method_defined?(:a11y_shop_confirm)
      alias_method :a11y_shop_confirm, :pbConfirm
      def pbConfirm(msg)
        A11yShop.say(msg)
        a11y_shop_confirm(msg)
      end
    end

    # ── Money on entering, and whenever it changes ──────────────────────────
    [:pbStartBuyScene, :pbStartSellScene].each do |meth|
      aliased = "a11y_shop_#{meth}".to_sym
      next unless method_defined?(meth)
      next if method_defined?(aliased)
      alias_method aliased, meth
      define_method(meth) do |*args|
        r = send(aliased, *args)
        begin
          @a11y_money = @adapter.getMoney
          A11yShop.say("You have #{A11yShop.money(@a11y_money)}.", interrupt: false)
        rescue Exception
        end
        r
      end
    end

    # pbRefresh redraws the money box; a purchase or sale changed the number.
    if method_defined?(:pbRefresh) && !method_defined?(:a11y_shop_refresh)
      alias_method :a11y_shop_refresh, :pbRefresh
      def pbRefresh
        r = a11y_shop_refresh
        begin
          now = @adapter.getMoney
          if !@a11y_money.nil? && now != @a11y_money
            A11yShop.say("You now have #{A11yShop.money(now)}.", interrupt: false)
          end
          @a11y_money = now
        rescue Exception
        end
        r
      end
    end

    # ── N reads the highlighted item's description ─────────────────────────
    if method_defined?(:update) && !method_defined?(:a11y_shop_update)
      alias_method :a11y_shop_update, :update
      def update
        a11y_shop_update
        begin
          if !@a11y_in_number && Input.triggerex?(0x4E)            # N
            win = @sprites && @sprites["itemwindow"]
            if win
              it = win.item
              if it.nil?
                A11yShop.say("Quit shopping.")
              else
                d = (@adapter.getDescription(it) rescue nil)
                A11yShop.say(d.to_s.empty? ? "No description." : d)
              end
            end
          end
        rescue Exception
        end
      end
    end

    # ── How many? Copied from Mart.rb:165, speech added ────────────────────
    def pbChooseNumber(helptext,item,maximum)
      curnumber=1
      ret=0
      helpwindow=@sprites["helpwindow"]
      itemprice=@adapter.getPrice(item,!@buying)
      itemprice/=2 if !@buying
      @a11y_in_number = true
      pbDisplay(helptext,true)             # speaks the question (see above)
      begin
        qty = @adapter.getQuantity(item)
        extra = []
        extra << "#{qty} in your bag" if @buying
        extra << "you have #{qty}" if !@buying
        extra << "you have #{A11yShop.money(@adapter.getMoney)}" if @buying
        A11yShop.say("#{A11yShop.amount_line(curnumber, itemprice)}. " +
                     extra.map { |e| e[0].upcase + e[1..-1] }.join(". ") + ". " +
                     "Up and down change by one, left and right by ten.",
                     interrupt: false)
      rescue Exception
      end
      using_block(numwindow=Window_AdvancedTextPokemon.new("")){ # Showing number of items
         qty=@adapter.getQuantity(item)
         using_block(inbagwindow=Window_AdvancedTextPokemon.new("")){ # Showing quantity in bag
            pbPrepareWindow(numwindow)
            pbPrepareWindow(inbagwindow)
            numwindow.viewport=@viewport
            numwindow.width=224
            numwindow.height=64
            numwindow.baseColor=Color.new(88,88,80)
            numwindow.shadowColor=Color.new(168,184,184)
            inbagwindow.visible=@buying
            inbagwindow.viewport=@viewport
            inbagwindow.width=190
            inbagwindow.height=64
            inbagwindow.baseColor=Color.new(88,88,80)
            inbagwindow.shadowColor=Color.new(168,184,184)
            inbagwindow.text=_ISPRINTF("In Bag:<r>{1:d}  ",qty)
            numwindow.text=_INTL("x{1}<r>$ {2}",curnumber,pbCommaNumber(curnumber*itemprice))
            pbBottomRight(numwindow)
            numwindow.y-=helpwindow.height
            pbBottomLeft(inbagwindow)
            inbagwindow.y-=helpwindow.height
            loop do
              Graphics.update
              Input.update
              numwindow.update
              inbagwindow.update
              self.update
              if Input.repeat?(Input::LEFT)
                pbPlayCursorSE()
                curnumber-=10
                curnumber=1 if curnumber<1
                numwindow.text=_INTL("x{1}<r>$ {2}",curnumber,pbCommaNumber(curnumber*itemprice))
                A11yShop.say(A11yShop.amount_line(curnumber, itemprice))
              elsif Input.repeat?(Input::RIGHT)
                pbPlayCursorSE()
                curnumber+=10
                curnumber=maximum if curnumber>maximum
                numwindow.text=_INTL("x{1}<r>$ {2}",curnumber,pbCommaNumber(curnumber*itemprice))
                A11yShop.say(A11yShop.amount_line(curnumber, itemprice))
              elsif Input.repeat?(Input::UP)
                pbPlayCursorSE()
                curnumber+=1
                curnumber=1 if curnumber>maximum
                numwindow.text=_INTL("x{1}<r>$ {2}",curnumber,pbCommaNumber(curnumber*itemprice))
                A11yShop.say(A11yShop.amount_line(curnumber, itemprice))
              elsif Input.repeat?(Input::DOWN)
                pbPlayCursorSE()
                curnumber-=1
                curnumber=maximum if curnumber<1
                numwindow.text=_INTL("x{1}<r>$ {2}",curnumber,pbCommaNumber(curnumber*itemprice))
                A11yShop.say(A11yShop.amount_line(curnumber, itemprice))
              elsif Input.trigger?(Input::C)
                pbPlayDecisionSE()
                ret=curnumber
                break
              elsif Input.trigger?(Input::B)
                pbPlayCancelSE()
                ret=0
                break
              end
            end
         }
      }
      helpwindow.visible=false
      return ret
    ensure
      @a11y_in_number = false
    end
  end
end
