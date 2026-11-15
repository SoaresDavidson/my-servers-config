-- @operation: user
-- @entity: batch
-- @name: PT-BR dual audio bonus
--
-- User op (camada "user" do Profilarr v2) aplicada sobre o banco Dictionarry.
-- Fica salva em pcd_ops (origin='user') e é recompilada depois das ops base, então
-- sobrevive aos pulls do Dictionarry. Aplicar com ../apply-user-ops.sh.
--
-- Preferência: áudio original sempre. PT-BR é só um bônus de desempate quando vem
-- junto do original (dual-audio). O ban do Dictionarry a releases sem Original/Inglês
-- ("Not Original or English", -999999) continua valendo, então dublado puro é rejeitado.
-- Scores dos perfis vão até ~1M: +20000 só decide entre releases de qualidade parecida.

-- --- BEGIN ( create custom_format "PT-BR Dual Audio" )
-- Original é obrigatório; entre os não obrigatórios do mesmo tipo basta um bater
-- (o parser dos *arr marca "Dublado"/"PT-BR" como Portuguese (Brazil); muitos
-- indexers marcam só "Portuguese").
insert into "custom_formats" ("name", "description") values ('PT-BR Dual Audio', 'Matches releases with both the Original and a Brazilian Portuguese (or Portuguese) audio track.');

INSERT INTO custom_format_conditions (custom_format_name, name, type, arr_type, negate, required)
VALUES ('PT-BR Dual Audio', 'Original', 'language', 'all', 0, 1);
INSERT INTO condition_languages (custom_format_name, condition_name, language_name, except_language) VALUES ('PT-BR Dual Audio', 'Original', 'Original', 0);

INSERT INTO custom_format_conditions (custom_format_name, name, type, arr_type, negate, required)
VALUES ('PT-BR Dual Audio', 'Portuguese (Brazil)', 'language', 'all', 0, 0);
INSERT INTO condition_languages (custom_format_name, condition_name, language_name, except_language) VALUES ('PT-BR Dual Audio', 'Portuguese (Brazil)', 'Portuguese (Brazil)', 0);

INSERT INTO custom_format_conditions (custom_format_name, name, type, arr_type, negate, required)
VALUES ('PT-BR Dual Audio', 'Portuguese', 'language', 'all', 0, 0);
INSERT INTO condition_languages (custom_format_name, condition_name, language_name, except_language) VALUES ('PT-BR Dual Audio', 'Portuguese', 'Portuguese', 0);

insert into "tags" ("name") values ('Language') on conflict ("name") do nothing;
INSERT INTO custom_format_tags (custom_format_name, tag_name) VALUES ('PT-BR Dual Audio', 'Language');
-- --- END

-- --- BEGIN ( score PT-BR Dual Audio in every profile )
INSERT INTO quality_profile_custom_formats (quality_profile_name, custom_format_name, arr_type, score)
SELECT name, 'PT-BR Dual Audio', 'all', 20000 FROM quality_profiles;
-- --- END
