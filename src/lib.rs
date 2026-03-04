use mlua::prelude::*;
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::sync::Mutex;
use tiktoken_rs::{
    CoreBPE, cl100k_base, o200k_base, o200k_harmony, p50k_base, p50k_edit, r50k_base,
};
// Cache tokenizers for performance
static CACHE: Lazy<Mutex<HashMap<String, CoreBPE>>> = Lazy::new(|| Mutex::new(HashMap::new()));

// Map model name → BPE initializer
fn tokenizer_for_model(model: &str) -> CoreBPE {
    let mut cache = CACHE.lock().unwrap();

    if let Some(bpe) = cache.get(model) {
        return bpe.clone();
    }

    let bpe = match model {
        // o200k_harmony
        "gpt-oss" | "gpt-oss-20b" | "gpt-oss-120b" => {
            o200k_harmony().expect("o200k_harmony failed")
        }

        // o200k_base
        "GPT-5" | "GPT-4.1" | "GPT-4o" | "o4" | "o3" | "o1" => {
            o200k_base().expect("o200k_base failed")
        }

        // cl100k_base
        "gpt-3.5-turbo" | "gpt-4" | "text-embedding-ada-002" => {
            cl100k_base().expect("cl100k_base failed")
        }

        // p50k_base
        "text-davinci-002" | "text-davinci-003" => p50k_base().expect("p50k_base failed"),

        // p50k_edit
        "text-davinci-edit-001" | "code-davinci-edit-001" => p50k_edit().expect("p50k_edit failed"),

        // r50k_base (GPT-3)
        "davinci" | "curie" | "babbage" | "ada" => r50k_base().expect("r50k_base failed"),

        // Fallback
        _ => cl100k_base().expect("fallback tokenizer"),
    };

    cache.insert(model.to_string(), bpe.clone());
    bpe
}

// Return token constants per model
fn model_constants(model: &str) -> (isize, isize) {
    match model {
        // Most recent GPT-3.5/4/4o models
        "gpt-3.5-turbo-0613"
        | "gpt-3.5-turbo-16k-0613"
        | "gpt-4-0314"
        | "gpt-4-32k-0314"
        | "gpt-4-0613"
        | "gpt-4-32k-0613"
        | "gpt-4o" => (3, 1),
        // March 2023 GPT-3.5-turbo
        "gpt-3.5-turbo-0301" => (4, -1),
        // For ambiguous "gpt-3.5-turbo" or "gpt-4", use latest known values
        m if m.starts_with("gpt-3.5-turbo") || m.starts_with("gpt-4") => (3, 1),
        // Fallback for unknown models
        _ => (3, 1),
    }
}

#[mlua::lua_module]
fn tiktoken(lua: &Lua) -> LuaResult<LuaTable> {
    let exports = lua.create_table()?;

    // Count raw text tokens
    let count_text = lua.create_function(|_, (text, model): (String, Option<String>)| {
        let model_name = model.unwrap_or_else(|| "cl100k_base".to_string());
        let bpe = tokenizer_for_model(&model_name);
        Ok(bpe.encode_with_special_tokens(&text).len())
    })?;

    // Count chat messages
    let count_messages =
        lua.create_function(|_, (messages, model): (LuaTable, Option<String>)| {
            let model_name = model.unwrap_or_else(|| "cl100k_base".to_string());
            let bpe = tokenizer_for_model(&model_name);
            let (tokens_per_message, tokens_per_name) = model_constants(&model_name);

            let mut total: usize = 0;

            for pair in messages.sequence_values::<LuaTable>() {
                let msg = pair?;

                if tokens_per_message > 0 {
                    total += tokens_per_message as usize;
                }

                if let Ok(role) = msg.get::<String>("role") {
                    total += bpe.encode_with_special_tokens(&role).len();
                }

                if let Ok(content) = msg.get::<String>("content") {
                    total += bpe.encode_with_special_tokens(&content).len();
                }

                if let Ok(name) = msg.get::<String>("name") {
                    total += bpe.encode_with_special_tokens(&name).len();
                    if tokens_per_name > 0 {
                        total += tokens_per_name as usize;
                    }
                }

                if let Ok(tool_calls) = msg.get::<LuaTable>("tool_calls") {
                    for tc in tool_calls.sequence_values::<LuaTable>() {
                        let tc = tc?;
                        if let Ok(func) = tc.get::<LuaTable>("function") {
                            if let Ok(name) = func.get::<String>("name") {
                                total += bpe.encode_with_special_tokens(&name).len();
                            }
                            if let Ok(args) = func.get::<String>("arguments") {
                                total += bpe.encode_with_special_tokens(&args).len();
                            }
                        }
                    }
                }
            }

            total += 3; // assistant priming
            Ok(total)
        })?;

    
    exports.set("count_text", count_text)?;
    exports.set("count_messages", count_messages)?;

    Ok(exports)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tokenizer_for_model_variants() {
        let models = vec![
            ("gpt-oss", "o200k_harmony"),
            ("GPT-5", "o200k_base"),
            ("gpt-3.5-turbo", "cl100k_base"),
            ("text-davinci-002", "p50k_base"),
            ("text-davinci-edit-001", "p50k_edit"),
            ("davinci", "r50k_base"),
            ("unknown", "cl100k_base"),
        ];
        for (model, _desc) in models {
            let bpe = tokenizer_for_model(model);
            // Just check that encoding works and returns a vector
            let tokens = bpe.encode_with_special_tokens("hello world");
            assert!(!tokens.is_empty());
        }
    }

    #[test]
    fn test_count_text_simple() {
        let bpe = tokenizer_for_model("cl100k_base");
        let text = "hello world";
        let tokens = bpe.encode_with_special_tokens(text);
        assert!(!tokens.is_empty());
    }

    #[test]
    fn test_count_messages_simple() {
        // Simulate a chat message structure
        let bpe = tokenizer_for_model("cl100k_base");
        let (tokens_per_message, tokens_per_name) = model_constants("cl100k_base");
        let role = "user";
        let content = "hello";
        let name = "bob";
        let mut total: usize = 0;
        if tokens_per_message > 0 {
            total += tokens_per_message as usize;
        }
        total += bpe.encode_with_special_tokens(role).len();
        total += bpe.encode_with_special_tokens(content).len();
        total += bpe.encode_with_special_tokens(name).len();
        if tokens_per_name > 0 {
            total += tokens_per_name as usize;
        }
        total += 3; // assistant priming
        assert!(total > 0);
    }
}
