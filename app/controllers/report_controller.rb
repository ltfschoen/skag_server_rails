# References:
# - https://developers.google.com/adwords/api/docs/appendix/reports
# - https://developers.google.com/adwords/api/docs/guides/reporting

class ReportController < ApplicationController

  # Define report definition. Alternatively pass XML text as string
  # Reference:
  # - https://developers.google.com/adwords/api/docs/guides/reporting#create_a_report_definition
  REPORT_DEFINITION_TEMPLATE = {
    :selector => {
      :fields => [],
      # Optional predicates
      # Reference: https://github.com/googleads/google-api-ads-ruby/tree/master/adwords_api/examples/v201705/basic_operations
    },
    :report_name => 'Last 7 days AdWords on Rails report',
    :report_type => nil,
    :download_format => nil,
    :date_range_type => 'LAST_7_DAYS'
  }

  def index
    @selected_account = selected_account
    @reports = Report.reports()
    @formats = ReportFormat.report_formats()
  end

  def get
    @selected_account = selected_account
    return if @selected_account.nil?

    validate_data(params)

    # AdWords API instance build from config: adwords_api.yml.erb
    api = get_adwords_api()
    report_utils = api.report_utils()
    definition = Report.create_definition(REPORT_DEFINITION_TEMPLATE, params)
    Rails.logger.info("# ReportController with params: #{params.to_yaml}")
    # Optional: Set configuration of API instance to suppress header,
    # column name, or summary rows in report output. Alternatively configure
    # in adwords_api.yml.erb configuration file.
    api.skip_report_header = 'on'.eql?(params[:report_header]) ? true : false
    api.skip_column_header = 'on'.eql?(params[:column_header]) ? true : false
    api.skip_report_summary = 'on'.eql?(params[:report_summary]) ? true : false
    # # Enable to allow rows with zero impressions to show.
    # api.include_zero_impressions = 'on'.eql?(params[:zeroes]) ? true : false
    api.use_raw_enum_values = 'on'.eql?(params[:raw_enum_values]) ? true : false
    begin
      # Only expect reports that fit into memory. Large reports
      # should be saved to files and served separately.
      # Note:
      # - Retrieve report as return value with `download_report`
      # - Download report using utility method `download_report_as_file`
      report_data = report_utils.download_report(definition)
      format = ReportFormat.report_format_for_type(params[:format])
      content_type = format.content_type
      filename = format.file_name(params[:type])
      Rails.logger.info("# ReportController with report_data: #{report_data.to_yaml}")
      Rails.logger.info("# ReportController with filename: #{filename.to_yaml}")

      # Daru DataFrame
      # - https://github.com/SciRuby/daru/blob/master/lib/daru/dataframe.rb
      require 'daru'
      require 'fastcsv'
      all = []
      FastCSV.raw_parse(report_data) { |row| all.push row }
      df = Daru::DataFrame.rows all[1..-1], order: all[1], index:(0..(all.length-2)).to_a
      # df = Daru::DataFrame.new([], order: (1..4).to_a, index:(0..10).to_a)
      Rails.logger.info("# Report Daru DataFrame: #{df}")

      df.row[1..(all.length-1)]
      df[1].type

      # name = df[5]
      # age  = df[6]
      #
      # df.plot type: :bar, x: name, y: age do |plot, diagram|
      #   plot.x_label "Name"
      #   plot.y_label "Age"
      #   plot.yrange [20,80]
      # end

      # require 'iruby'
      # require 'nyaplot'
      # plot = Nyaplot::Plot.new
      # sc = plot.add(:scatter, [0,1,2,3,4], [-1,2,-3,4,-5])
      # color = Nyaplot::Colors.qual
      # sc.color(color)

      # require 'iruby/rails'
      # IRuby.load_rails
      # # plot.show # show plot on IRuby notebook
      # plot.export_html # export plot to the current directory as a html file

      # send_data(report_data, {
      require 'prawn'
      send_data(generate_pdf(report_data), {
          # :filename => filename,
          :filename => "#{filename}.pdf",
          # :type => content_type,
          type: "application/pdf",
          :disposition => 'inline'
      })
      puts "Report was downloaded to '%s'." % filename
    rescue AdwordsApi::Errors::ReportError => e
      @error = e.message
    end
  end

  def sqr_example
    sample_xml = File.open("search_query_report_example.xml") { |f| Nokogiri::XML(f) }
    Rails.logger.info("# ReportController with sample_xml: #{sample_xml.to_yaml}")
    @sample_xml = sample_xml
  end

  private

  def validate_data(data)
    format = ReportFormat.report_format_for_type(data[:format])
    raise StandardError, 'Unknown format' if format.nil?
    report = Report.report_for_type(data[:type])
    raise StandardError, 'Unknown report type' if report.nil?
  end

  # Reference Action Controller Documentation
  def generate_pdf(report_data)
    Prawn::Document.new do
      text report_data
    end.render
  end
end
