import styles from "../styles/movie-videos.module.css";

const URL = "https://nomad-movies.nomadcoders.workers.dev/movies";

async function getVideos(id: string) {
  const response = await fetch(`${URL}/${id}/videos`);
  return response.json();
}

export default async function VideosInfo({ id }: { id: string }) {
  const videos = await getVideos(id);
  return (
    <div className={styles.container}>
      {videos.map((video: any) => (
        <iframe
          key={video.id}
          src={`https://youtube.com/embed/${video.key}`}
          title={video.name}
          allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
          allowFullScreen
        />
      ))}
    </div>
  );
}