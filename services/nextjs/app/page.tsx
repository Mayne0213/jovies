import styles from "../styles/home.module.css";
import Movie from "@/components/movie";

const URL = "https://nomad-movies.nomadcoders.workers.dev/movies";

export const metadata = {
  title: "Jovies",
};

async function getMovies() {
  const response = await fetch(URL);
  const json = await response.json();
  return json;
}

export default async function HomePage() {
  const movies = await getMovies();
  return (
    <div className={styles.container}>
      {movies.map((movie: any) => (
        <Movie
          key={movie.id}
          id={movie.id}
          poster_path={movie.poster_path}
          title={movie.title}
        ></Movie>
      ))}
    </div>
  );
}
