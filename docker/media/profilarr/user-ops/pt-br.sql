-- @operation: user
-- @entity: batch
-- @name: PT-BR audio custom formats
--
-- User op (camada "user" do Profilarr v2) aplicada sobre o banco Dictionarry.
-- Fica salva em pcd_ops (origin='user') e é recompilada depois das ops base, então
-- sobrevive aos pulls do Dictionarry. Aplicar com ../apply-user-ops.sh.
--
-- Pontuação final (os dois CFs se somam):
--   só dublado PT-BR       -> +100000
--   dual (original + PT-BR) -> +150000
-- Scores dos perfis vão até ~1M (upgrade_until 1M, mínimo 200k): é um desempate forte,
-- não pula vários degraus de qualidade.

-- --- BEGIN ( create custom_format "PT-BR Audio" )
-- O Radarr/Sonarr detectam "Dublado"/"PT-BR" no nome como Portuguese (Brazil); muitos
-- indexers marcam só "Portuguese". Condições do mesmo tipo, não obrigatórias = OU.
insert into "custom_formats" ("name", "description") values ('PT-BR Audio', 'Matches releases with a Brazilian Portuguese (or Portuguese) audio track.');

INSERT INTO custom_format_conditions (custom_format_name, name, type, arr_type, negate, required)
VALUES ('PT-BR Audio', 'Portuguese (Brazil)', 'language', 'all', 0, 0);
INSERT INTO condition_languages (custom_format_name, condition_name, language_name, except_language) VALUES ('PT-BR Audio', 'Portuguese (Brazil)', 'Portuguese (Brazil)', 0);

INSERT INTO custom_format_conditions (custom_format_name, name, type, arr_type, negate, required)
VALUES ('PT-BR Audio', 'Portuguese', 'language', 'all', 0, 0);
INSERT INTO condition_languages (custom_format_name, condition_name, language_name, except_language) VALUES ('PT-BR Audio', 'Portuguese', 'Portuguese', 0);

insert into "tags" ("name") values ('Language') on conflict ("name") do nothing;
INSERT INTO custom_format_tags (custom_format_name, tag_name) VALUES ('PT-BR Audio', 'Language');
-- --- END

-- --- BEGIN ( create custom_format "PT-BR Dual Audio" )
-- Original é obrigatório; entre os não obrigatórios do mesmo tipo basta um bater.
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

INSERT INTO custom_format_tags (custom_format_name, tag_name) VALUES ('PT-BR Dual Audio', 'Language');
-- --- END

-- --- BEGIN ( score PT-BR CFs in every profile )
INSERT INTO quality_profile_custom_formats (quality_profile_name, custom_format_name, arr_type, score)
SELECT name, 'PT-BR Audio', 'all', 100000 FROM quality_profiles;
INSERT INTO quality_profile_custom_formats (quality_profile_name, custom_format_name, arr_type, score)
SELECT name, 'PT-BR Dual Audio', 'all', 50000 FROM quality_profiles;
-- --- END

-- --- BEGIN ( allow dubbed-only releases )
-- Os perfis do Dictionarry banem (-999999) releases sem faixa Original/Inglês, o que
-- rejeita o dublado puro. Guardado no valor antigo: se o upstream mudar, não sobrescreve.
update "quality_profile_custom_formats" set "score" = 0
where "custom_format_name" = 'Not Original or English' and "score" = -999999;
-- --- END
