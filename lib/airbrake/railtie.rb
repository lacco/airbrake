require 'airbrake'
require 'rails'

require 'airbrake/rails/middleware'

module Airbrake
  class Railtie < ::Rails::Railtie
    rake_tasks do
      require 'airbrake/rake_handler'
      require 'airbrake/rails3_tasks'
    end

    initializer "airbrake.middleware" do |app|
      app.config.middleware.use "Airbrake::Rails::Middleware"
      app.config.middleware.insert 0, "Airbrake::UserInformer"
      app.config.middleware.use "Airbrake::Metrics"
    end

    config.after_initialize do
      Airbrake.configure(true) do |config|
        config.logger           ||= config.async? ? ::Logger.new(STDERR) : ::Rails.logger
        config.environment_name ||= ::Rails.env
        config.project_root     ||= ::Rails.root
        config.framework        = "Rails: #{::Rails::VERSION::STRING}"
      end

      ActiveSupport.on_load(:action_controller) do
        # Lazily load action_controller methods
        #
        require 'airbrake/rails/controller_methods'

        include Airbrake::Rails::ControllerMethods
      end

      if defined?(::ActionController::Base)
        require 'airbrake/rails/javascript_notifier'

        ::ActionController::Base.send(:include, Airbrake::Rails::JavascriptNotifier)
      end

      ActiveSupport::Notifications.subscribe "process_action.action_controller" do |name, start, finish, id, payload|

        time = (finish - start) * 1000000 #in micro seconds

        Airbrake::Metrics.tap do |m|

          m.duration_of_requests += time
          m.request_counter += 1
          m.avg = 0 if m.avg.nil?
          m.avg = m.duration_of_requests / m.request_counter

          m.min_response_time ||= time
          m.max_response_time ||= time

          if time < m.min_response_time
            m.min_response_time = time
          end

          if time > m.max_response_time
            m.max_response_time = time
          end
        end
      end
    end
  end
end
