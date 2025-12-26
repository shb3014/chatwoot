# Service to validate that assistant responses only use information from retrieved documentation
class Captain::ResponseValidatorService
  attr_reader :tool_results, :conversation_context

  # Validation strictness levels
  STRICT = :strict     # Reject responses with any hallucination indicators
  MODERATE = :moderate # Warn but allow responses with low-confidence hallucination
  LENIENT = :lenient   # Only log warnings, never reject

  def initialize(strictness: MODERATE)
    @tool_results = []
    @strictness = strictness
    @conversation_context = :unknown # :greeting, :ongoing, :unknown
  end
  
  # Set conversation context based on message history
  def set_conversation_context(messages)
    if messages.nil? || messages.empty?
      @conversation_context = :greeting
      return
    end
    
    # Count substantive messages (not just tool calls or system messages)
    substantive_messages = messages.count { |m| m['role'] == 'user' || (m['role'] == 'assistant' && m['content'].present?) }
    
    @conversation_context = substantive_messages > 1 ? :ongoing : :greeting
    Rails.logger.info "ResponseValidator: Conversation context set to #{@conversation_context} (#{substantive_messages} substantive messages)"
  end

  def strict?
    @strictness == STRICT
  end

  def moderate?
    @strictness == MODERATE
  end

  def lenient?
    @strictness == LENIENT
  end

  # Capture tool execution results
  def capture_tool_result(tool_name, result)
    @tool_results << {
      tool: tool_name,
      content: result,
      timestamp: Time.current
    }
    Rails.logger.info "ResponseValidator: Captured result from #{tool_name}"
  end

  # Get all captured documentation content
  def get_documentation_content
    @tool_results
      .select { |r| r[:tool] == 'search_documentation' }
      .map { |r| r[:content] }
      .join("\n")
  end

  # Validate if response appears to use only documented information
  # Returns: { valid: boolean, reason: string, confidence: float, should_reject: boolean }
  def validate_response(response_text)
    documentation = get_documentation_content
    
    # If model responded without searching documentation, check if that's acceptable
    if @tool_results.empty?
      # In an ONGOING conversation, nearly ALL responses need documentation search
      if @conversation_context == :ongoing
        # Check if it's a fallback message (which is acceptable)
        is_fallback = response_text.include?("I couldn't find") ||
                     response_text.include?("I don't have that information") ||
                     response_text.include?("speak with a support agent") ||
                     response_text.include?("Unable to provide accurate information")
        
        if is_fallback
          # Fallback messages are okay even in ongoing conversation
          return { valid: true, reason: 'Appropriate fallback response', confidence: 1.0, should_reject: false }
        else
          # Any other response during ongoing conversation without search is HIGHLY suspicious
          should_reject = should_reject_based_on_strictness(0.1)
          return {
            valid: false,
            reason: 'Model responded in ongoing conversation without searching documentation (likely hallucination)',
            confidence: 0.1,
            indicators: ['no_tool_calls', 'ongoing_conversation_without_search'],
            should_reject: should_reject
          }
        end
      end
      
      # For NEW/GREETING conversations, check if it's an acceptable greeting
      is_greeting = response_text.downcase.match?(/^(hello|hi|hey|greetings)/i) ||
                   response_text.match?(/\b(how can I|what can I|help you)\b/i)
      
      is_fallback = response_text.include?("I couldn't find") ||
                   response_text.include?("I don't have that information") ||
                   response_text.include?("speak with a support agent")
      
      is_thanks_goodbye = response_text.downcase.match?(/\b(thank|thanks|goodbye|bye|see you)\b/)
      
      # Product information or troubleshooting without search is suspicious
      contains_product_info = response_text.match?(/\b(connect|wifi|battery|setup|configure|install|troubleshoot|error|issue|problem)\b/i)
      contains_specific_steps = response_text.match?(/\b(first|next|then|step|ensure|make sure|check)\b/i) && response_text.length > 80
      
      if is_greeting || is_fallback || is_thanks_goodbye
        # These are okay without documentation
        return { valid: true, reason: 'Appropriate response without needing documentation', confidence: 1.0, should_reject: false }
      elsif contains_product_info || contains_specific_steps
        # Product information or detailed steps without search is hallucination
        should_reject = should_reject_based_on_strictness(0.2)
        return {
          valid: false,
          reason: 'Model provided product information or troubleshooting steps without searching documentation',
          confidence: 0.2,
          indicators: ['no_tool_calls', 'product_info_without_search'],
          should_reject: should_reject
        }
      else
        # Other responses without search - warn but allow based on strictness
        should_reject = should_reject_based_on_strictness(0.5)
        return {
          valid: !should_reject,
          reason: 'Response without documentation search',
          confidence: 0.5,
          indicators: ['no_tool_calls'],
          should_reject: should_reject
        }
      end
    end

    # If no documentation was found, response should indicate this
    if documentation.blank? || documentation.include?('No documentation found')
      result = validate_no_docs_response(response_text)
      result[:should_reject] = !result[:valid] && should_reject_based_on_strictness(result[:confidence])
      return result
    end

    # Check if response contains common hallucination patterns
    hallucination_indicators = detect_hallucination_patterns(response_text, documentation)

    if hallucination_indicators.any?
      confidence = calculate_confidence(hallucination_indicators.size)
      should_reject = should_reject_based_on_strictness(confidence)
      
      return {
        valid: false,
        reason: "Possible hallucination detected: #{hallucination_indicators.join(', ')}",
        confidence: confidence,
        indicators: hallucination_indicators,
        should_reject: should_reject
      }
    end

    {
      valid: true,
      reason: 'Response appears to be based on documentation',
      confidence: 0.8,
      should_reject: false
    }
  end

  # Clear captured tool results (called at the start of each new conversation turn)
  def clear
    @tool_results = []
  end

  private

  def should_reject_based_on_strictness(confidence)
    case @strictness
    when STRICT
      confidence < 0.7  # Reject if confidence is low
    when MODERATE
      confidence < 0.4  # Only reject very low confidence
    when LENIENT
      false  # Never reject
    else
      confidence < 0.5
    end
  end

  def calculate_confidence(num_indicators)
    # More indicators = lower confidence
    base_confidence = 0.5
    penalty = num_indicators * 0.1
    [base_confidence - penalty, 0.1].max
  end

  private

  def validate_no_docs_response(response_text)
    # When no docs found, response should acknowledge this
    acceptable_phrases = [
      'no information',
      'not found',
      'couldn\'t find',
      'don\'t have',
      'documentation doesn\'t',
      'support agent',
      'support person'
    ]

    has_acceptable_phrase = acceptable_phrases.any? { |phrase| response_text.downcase.include?(phrase) }

    if has_acceptable_phrase
      {
        valid: true,
        reason: 'Correctly indicates information not found',
        confidence: 0.9
      }
    else
      {
        valid: false,
        reason: 'Response provides information when documentation search returned no results',
        confidence: 0.2
      }
    end
  end

  def detect_hallucination_patterns(response_text, documentation)
    indicators = []

    # Check for specific technical details that aren't in documentation
    # This is a heuristic approach - can be enhanced based on your use case

    # Pattern 1: Specific numbers/versions not in docs
    response_numbers = extract_numbers_and_versions(response_text)
    doc_numbers = extract_numbers_and_versions(documentation)

    suspicious_numbers = response_numbers - doc_numbers
    if suspicious_numbers.any? && response_numbers.size > 2
      # Only flag if there are multiple specific numbers and some aren't in docs
      # This avoids false positives from generic numbers like "1" or "2"
      specific_suspicious = suspicious_numbers.select { |n| n.length > 1 || n.to_i > 10 }
      if specific_suspicious.any?
        indicators << "mentions specific values not in documentation: #{specific_suspicious.first(3).join(', ')}"
      end
    end

    # Pattern 2: Response is too long compared to available documentation
    # If response has lots of detail but docs are sparse, likely hallucinating
    if documentation.length < 200 && response_text.length > 300
      indicators << "response is suspiciously detailed given sparse documentation"
    end

    # Pattern 3: Common knowledge phrases that suggest using training data
    training_data_phrases = [
      'generally',
      'typically',
      'usually',
      'in most cases',
      'commonly',
      'it is known that',
      'as you may know'
    ]

    found_phrases = training_data_phrases.select { |phrase| response_text.downcase.include?(phrase) }
    if found_phrases.any?
      indicators << "uses general knowledge phrases: #{found_phrases.first(2).join(', ')}"
    end

    indicators
  end

  def extract_numbers_and_versions(text)
    # Extract numbers, versions, and technical specs
    numbers = []

    # Version numbers (e.g., "2.5", "v1.0", "3.2.1")
    numbers += text.scan(/\b(?:v|version\s*)?(\d+(?:\.\d+)+)\b/i).flatten

    # Standalone numbers with context (e.g., "2000mAh", "9 hours", "80%")
    numbers += text.scan(/\b(\d+(?:\.\d+)?(?:mah|gb|mb|hours?|minutes?|%|hz|ghz)?)\b/i).flatten

    # Clean and deduplicate
    numbers.map(&:downcase).uniq
  end
end

