R36LLM_APP_SITE = $(BR2_EXTERNAL_R36LLM_PATH)/../app
R36LLM_APP_SITE_METHOD = local
R36LLM_APP_DEPENDENCIES = prism-llama-cpp

$(eval $(cmake-package))
