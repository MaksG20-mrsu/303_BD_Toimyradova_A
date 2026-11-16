#!/bin/bash
chcp 65001

sqlite3 movies_rating.db < db_init.sql

echo "1. Для каждого фильма выведите его название, год выпуска и средний рейтинг. Дополнительно добавьте столбец rank_by_avg_rating, в котором укажите ранг фильма среди всех фильмов по убыванию среднего рейтинга (фильмы с одинаковым средним рейтингом должны получить одинаковый ранг). Используйте оконную функцию RANK() или DENSE_RANK(). В результирующем наборе данных оставить 10 фильмов с наибольшим рангом."
echo --------------------------------------------------
sqlite3 movies_rating.db -box -echo "
SELECT
    m.title,
    m.year,
    ROUND(AVG(r.rating), 4) AS avg_rating,
    DENSE_RANK() OVER (ORDER BY AVG(r.rating) DESC) AS rank_by_avg_rating
FROM movies m
JOIN ratings r ON r.movie_id = m.id
GROUP BY m.id, m.title, m.year
ORDER BY rank_by_avg_rating
LIMIT 10;
"
echo " "

echo "2. С помощью рекурсивного CTE выделить все жанры фильмов, имеющиеся в таблице movies. Для каждого жанра рассчитать средний рейтинг avg_rating фильмов в этом жанре. Выведите genre, avg_rating и ранг жанра по убыванию среднего рейтинга, используя оконную функцию RANK()."
echo --------------------------------------------------
sqlite3 movies_rating.db -box -echo "
WITH RECURSIVE split(movie_id, genre, rest) AS (
    SELECT id, '', genres || '|' FROM movies
    UNION ALL
    SELECT movie_id,
           substr(rest, 1, instr(rest, '|') - 1),
           substr(rest, instr(rest, '|') + 1)
    FROM split WHERE rest <> ''
),
movie_genres AS (
    SELECT DISTINCT movie_id, genre FROM split WHERE genre <> ''
),
genre_ratings AS (
    SELECT mg.genre, AVG(r.rating) AS avg_rating
    FROM movie_genres mg
    JOIN ratings r ON r.movie_id = mg.movie_id
    GROUP BY mg.genre
)
SELECT genre,
       ROUND(avg_rating, 4) AS avg_rating,
       RANK() OVER (ORDER BY avg_rating DESC) AS genre_rank
FROM genre_ratings
ORDER BY genre_rank;
"
echo " "

echo "3. Посчитайте количество фильмов в каждом жанре. Выведите два столбца: genre и movie_count, отсортировав результат по убыванию количества фильмов."
echo --------------------------------------------------
sqlite3 movies_rating.db -box -echo "
WITH RECURSIVE split(movie_id, genre, rest) AS (
    SELECT id, '', genres || '|' FROM movies
    UNION ALL
    SELECT movie_id,
           substr(rest, 1, instr(rest, '|') - 1),
           substr(rest, instr(rest, '|') + 1)
    FROM split WHERE rest <> ''
),
movie_genres AS (
    SELECT DISTINCT movie_id, genre FROM split WHERE genre <> ''
)
SELECT genre,
       COUNT(*) AS movie_count
FROM movie_genres
GROUP BY genre
ORDER BY movie_count DESC, genre;
"
echo " "

echo "4. Найдите жанры, в которых чаще всего оставляют теги (комментарии). Для этого подсчитайте общее количество записей в таблице tags для фильмов каждого жанра. Выведите genre, tag_count и долю этого жанра в общем числе тегов (tag_share), выраженную в процентах."
echo --------------------------------------------------
sqlite3 movies_rating.db -box -echo "
WITH RECURSIVE split(movie_id, genre, rest) AS (
    SELECT id, '', genres || '|' FROM movies
    UNION ALL
    SELECT movie_id,
           substr(rest, 1, instr(rest, '|') - 1),
           substr(rest, instr(rest, '|') + 1)
    FROM split WHERE rest <> ''
),
movie_genres AS (
    SELECT DISTINCT movie_id, genre FROM split WHERE genre <> ''
),
genre_tags AS (
    SELECT mg.genre, COUNT(t.id) AS tag_count
    FROM movie_genres mg
    JOIN tags t ON t.movie_id = mg.movie_id
    GROUP BY mg.genre
)
SELECT genre,
       tag_count,
       ROUND(tag_count * 100.0 / (SELECT COUNT(*) FROM tags), 2) AS tag_share
FROM genre_tags
ORDER BY tag_count DESC;
"
echo " "

echo "5. Для каждого пользователя рассчитайте: общее количество выставленных оценок, средний выставленный рейтинг, дату первой и последней оценки (по полю timestamp в таблице ratings). Выведите user_id, rating_count, avg_rating, first_rating_date, last_rating_date. Отсортируйте результат по убыванию количества оценок и выведите только 10 первых строк."
echo --------------------------------------------------
sqlite3 movies_rating.db -box -echo "
SELECT user_id,
       COUNT(*) AS rating_count,
       ROUND(AVG(rating), 4) AS avg_rating,
       MIN(timestamp) AS first_rating_date,
       MAX(timestamp) AS last_rating_date
FROM ratings
GROUP BY user_id
ORDER BY rating_count DESC, user_id
LIMIT 10;
"
echo " "

echo "6. Сегментируйте пользователей по типу поведения: «Комментаторы» — пользователи, у которых количество тегов больше количества оценок; «Оценщики» — наоборот, оценок больше, чем тегов; «Активные» — и оценок, и тегов >= 10; «Пассивные» — и оценок, и тегов < 5. Выведите user_id, общее число оценок, общее число тегов и категорию поведения. Используйте CASE."
echo --------------------------------------------------
sqlite3 movies_rating.db -box -echo "
WITH user_stats AS (
    SELECT u.id AS user_id,
           COALESCE(r.rating_count, 0) AS rating_count,
           COALESCE(t.tag_count, 0) AS tag_count
    FROM users u
    LEFT JOIN (SELECT user_id, COUNT(*) AS rating_count FROM ratings GROUP BY user_id) r ON r.user_id = u.id
    LEFT JOIN (SELECT user_id, COUNT(*) AS tag_count FROM tags GROUP BY user_id) t ON t.user_id = u.id
)
SELECT user_id,
       rating_count,
       tag_count,
       CASE
           WHEN rating_count >= 10 AND tag_count >= 10 THEN 'Активные'
           WHEN tag_count > rating_count THEN 'Комментаторы'
           WHEN rating_count > tag_count THEN 'Оценщики'
           WHEN rating_count < 5 AND tag_count < 5 THEN 'Пассивные'
           ELSE 'Пассивные'
       END AS category
FROM user_stats
ORDER BY user_id;
"
echo " "

echo "7. Для каждого пользователя выведите его имя и последний фильм, который он оценил (по времени из ratings.timestamp). Если пользователь не оценивал ни одного фильма, он всё равно должен быть в результате (с NULL в полях фильма). Результат: user_id, name, last_rated_movie_title, last_rating_timestamp."
echo --------------------------------------------------
sqlite3 movies_rating.db -box -echo "
WITH last_rating AS (
    SELECT r.user_id,
           r.movie_id,
           r.timestamp,
           ROW_NUMBER() OVER (PARTITION BY r.user_id ORDER BY r.timestamp DESC, r.id DESC) AS rn
    FROM ratings r
)
SELECT u.id AS user_id,
       u.name,
       m.title AS last_rated_movie_title,
       lr.timestamp AS last_rating_timestamp
FROM users u
LEFT JOIN last_rating lr ON lr.user_id = u.id AND lr.rn = 1
LEFT JOIN movies m ON m.id = lr.movie_id
ORDER BY u.id;
"
echo " "