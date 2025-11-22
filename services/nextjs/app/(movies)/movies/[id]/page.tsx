import { Suspense } from "react";
import MovieInfo from "@/components/movie-info";
import VideosInfo from "@/components/movie-videos";
import { getMovie } from "@/components/movie-info";

interface Iparams {
  params: { id: string };
}

export async function generateMetadata({ params: { id } }: Iparams) {
  const movie = await getMovie(id);
  return { title: movie.title };
}

export default async function MovieDetail({ params: { id } }: Iparams) {
  return (
    <div>
      <Suspense fallback={<h1>Loading movie info</h1>}>
        <MovieInfo id={id} />
      </Suspense>
      <Suspense fallback={<h1>Loading videos info</h1>}>
        <VideosInfo id={id} />
      </Suspense>
    </div>
  );
}
