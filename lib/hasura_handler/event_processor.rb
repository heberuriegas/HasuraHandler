module HasuraHandler
  class EventProcessor
    attr_accessor :event
    attr_accessor :errors

    def initialize(event)
      @event = HasuraHandler::Event.new(event)
      @errors = {}
    end

    def process_later
      unless event_handlers.present?
        log_missing_handler
        return
      end

      HasuraHandler::EventJob.perform_later(@event.raw_event)
    end

    def process
      unless event_handlers.present?
        log_missing_handler
        return
      end

      event_handlers.each do |handler_class|
        if HasuraHandler.fanout_events
          HasuraHandler::EventHandlerJob.perform_later(handler_class.to_s, @event.raw_event)
        else
          handler = handler_class.new(@event)
          handler.run
        end
      end
    end

    private

    def log_missing_handler
      errors['hasura_handler'] = 'Received event with no matching handlers.'
    end

    def event_handlers
      HasuraHandler::EventHandler.
      descendants.
      map{ |klass| [klass, klass.hasura_matchers] }.
      to_h.
      select{ |klass,matchers| matchers.present? }.
      map{ |klass,matchers| [klass, check_matchers(matchers)] }.
      to_h.
      select{ |klass,match| match }.
      keys
    end

    def check_matchers(matchers)
      matchers.all? do |field,value|
        @event.send(field) == value
      end
    end
  end
end
