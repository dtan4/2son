require 'test_helper'

class ThreadControllerTest < ActionController::TestCase
  test "should get json" do
    get :json
    assert_response :success
  end

  test "should get jsonp" do
    get :jsonp
    assert_response :success
  end

end
